// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft is ERC721Enumerable, Owned {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant INSIDER_MINTS             = 300; 
  uint public constant PUBLIC_MINTS              = 1700; 
  uint public constant MIN_COLLATERIZATION_RATIO = 3e18; // 300%

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  struct Permission {
    bool    hasPermission; 
    uint248 lastUpdated;
  }

  mapping(uint => uint)                            public id2eth;
  mapping(uint => uint)                            public id2dyad;
  mapping(uint => mapping (address => Permission)) public id2permission; 
  mapping(uint => uint)                            public id2lastOwnershipChange; 

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  event MintNft  (uint indexed id, address indexed to);
  event Deposit  (uint indexed id, uint amount);
  event Withdraw (uint indexed from, address indexed to, uint amount);
  event MintDyad (uint indexed from, address indexed to, uint amount);
  event Liquidate(uint indexed id, address indexed to);
  event Redeem   (uint indexed from, uint amount, address indexed to, uint eth);
  event Grant    (uint indexed id, address indexed operator);
  event Revoke   (uint indexed id, address indexed operator);

  error NotOwner            ();
  error StaleData           ();
  error CrTooLow            ();
  error CrTooHigh           ();
  error IncompleteRound     ();
  error PublicMintsExceeded ();
  error InsiderMintsExceeded();
  error MissingPermission   ();

  modifier isNftOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
  }
  modifier isNftOwnerOrHasPermission(uint id) {
    if (!hasPermission(id, msg.sender)) revert MissingPermission() ; _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      address _owner
  ) ERC721("Dyad NFT", "dNFT") 
    Owned(_owner) {
      dyad   = Dyad(_dyad);
      oracle = IAggregatorV3(_oracle);
  }

  function mintNft(address to)
    external 
    returns (uint) {
      if (++publicMints > PUBLIC_MINTS) revert PublicMintsExceeded();
      return _mintNft(to);
  }

  function mintInsiderNft(address to)
    external 
      onlyOwner
    returns (uint) {
      if (++insiderMints > INSIDER_MINTS) revert InsiderMintsExceeded();
      return _mintNft(to); 
  }

  // Mint new DNft to `to`
  function _mintNft(address to)
    private 
    returns (uint) {
      uint id = totalSupply();
      _safeMint(to, id);
      emit MintNft(id, to);
      return id;
  }

  // Deposit ETH
  function deposit(uint id) 
    external 
    payable
  {
    id2eth[id] += msg.value;
    emit Deposit(id, msg.value);
  }

  // Withdraw ETH
  function withdraw(uint from, address to, uint amount) 
    external 
      isNftOwnerOrHasPermission(from) 
    {
      id2eth[from] -= amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      to.safeTransferETH(amount); 
      emit Withdraw(from, to, amount);
  }

  // Mint DYAD
  function mintDyad(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
    {
      id2dyad[from] += amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      dyad.mint(to, amount);
      emit MintDyad(from, to, amount);
  }

  function liquidate(uint id, address to) 
    external 
    payable {
      if (_collatRatio(id) >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh(); 
      id2eth[id] += msg.value;
      if (_collatRatio(id) <  MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      _transfer(ownerOf(id), to, id);
      emit Liquidate(id, to);
  }

  // Redeem DYAD for ETH
  function redeem(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
    returns (uint) { 
      dyad.burn(msg.sender, amount);
      id2dyad[from] -= amount;
      uint eth       = amount*1e8 / _getEthPrice();
      id2eth[from]  -= eth;
      to.safeTransferETH(eth); // re-entrancy 
      emit Redeem(from, amount, to, eth);
      return eth;
  }

  function grant(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      id2permission[id][operator] = Permission(true, uint248(block.number));
      emit Grant(id, operator);
  }

  function revoke(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      delete id2permission[id][operator];
      emit Revoke(id, operator);
  }

  function hasPermission(uint id, address operator) 
    public 
    view 
    returns (bool) {
      return (
        ownerOf(id) == operator || 
        (
          id2permission[id][operator].hasPermission && 
          id2permission[id][operator].lastUpdated > id2lastOwnershipChange[id]
        )
      );
  }

  // Get Collateralization Ratio of the dNFT
  function _collatRatio(uint id) 
    private 
    view 
    returns (uint) {
      uint _dyad = id2dyad[id]; // save gas
      if (_dyad == 0) return type(uint).max;
      // cr = deposit / withdrawn
      return (id2eth[id] * _getEthPrice()/1e8).divWadDown(_dyad);
  }

  // ETH price in USD
  function _getEthPrice() 
    private 
    view 
    returns (uint) {
      (
        uint80 roundID,
        int256 price,
        , 
        uint256 timeStamp, 
        uint80 answeredInRound
      ) = oracle.latestRoundData();
      if (timeStamp == 0) revert IncompleteRound();
      if (answeredInRound < roundID) revert StaleData();
      return price.toUint256();
  }

  // We have to set `lastOwnershipChange` in order to reset permissions
  function _beforeTokenTransfer(
      address from,
      address to,
      uint256 id, 
      uint256 batchSize 
  ) internal 
    override {
      super._beforeTokenTransfer(from, to, id, batchSize);
      id2lastOwnershipChange[id] = block.number; // resets permissions
  }
}

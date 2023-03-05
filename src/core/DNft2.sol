// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft2 is ERC721Enumerable, Owned {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant INSIDER_MINTS             = 300; 
  uint public constant PUBLIC_MINTS              = 1700; 
  uint public constant MIN_COLLATERIZATION_RATIO = 3e18; // 300%

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  mapping(uint => uint) public id2eth;
  mapping(uint => uint) public id2dyad;

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  error NotOwner            ();
  error StaleData           ();
  error CrTooLow            ();
  error CrTooHigh           ();
  error IncompleteRound     ();
  error PublicMintsExceeded ();
  error InsiderMintsExceeded();

  modifier isNftOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
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
    payable 
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
      return id;
  }

  // Deposit ETH
  function deposit(uint id) 
    external 
    payable
  {
    id2eth[id] += msg.value;
  }

  // Withdraw ETH
  function withdraw(uint from, address to, uint amount) 
    external 
      isNftOwner(from) 
    {
      id2eth[from] -= amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      to.safeTransferETH(amount); 
  }

  // Mint DYAD
  function mint(uint from, address to, uint amount)
    external 
      isNftOwner(from)
    {
      id2dyad[from] += amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      dyad.mint(to, amount);
  }

  function liquidate(uint id, address to) 
    external 
    payable {
      if (_collatRatio(id) >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh(); 
      id2eth[id] += msg.value;
      if (_collatRatio(id) <  MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      _transfer(ownerOf(id), to, id);
  }

  // Redeem DYAD for ETH
  function redeem(uint from, address to, uint amount)
    external 
      isNftOwner(from)
    returns (uint) { 
      dyad.burn(msg.sender, amount);
      id2dyad[from] -= amount;
      uint eth = _dyad2eth(amount);
      id2eth[from]  -= eth;
      to.safeTransferETH(eth); // re-entrancy 
      return eth;
  }

  // Get Collateralization Ratio of the dNFT
  function _collatRatio(uint id) 
    private 
    view 
    returns (uint) {
      uint _dyad = id2dyad[id]; // save gas
      if (_dyad == 0) return type(uint).max;
      // cr = deposit / withdrawn
      return _dyad.divWadDown(_eth2dyad(id2eth[id]));
  }

  // Return the value of DYAD in ETH
  function _dyad2eth(uint _dyad)
    private 
    view 
    returns (uint) {
      return _dyad*1e8 / _getEthPrice();
  }

  // Return the value of ETH in DYAD
  function _eth2dyad(uint eth) 
    private 
    view 
    returns (uint) {
      return eth * _getEthPrice()/1e8; 
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
}

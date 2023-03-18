// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IDNft} from "../interfaces/IDNft.sol";
import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";
import {Nft} from "./Nft.sol";

contract DNftERC20 {
  using SafeTransferLib   for address;
  using SafeCast          for int;
  using FixedPointMathLib for uint;

  error StaleData            ();
  error IncompleteRound      ();
  error CrTooLow             ();
  error CrTooHigh            ();
  error InvalidNft           ();
  error NotOwner             ();
  error MissingPermission    ();

  event Deposit  (uint indexed id, uint amount);
  event Redeem   (uint indexed from, uint amount, address indexed to, uint eth);
  event Liquidate(uint indexed id, address indexed to);
  event Withdraw (uint indexed from, address indexed to, uint amount);
  event MintDyad (uint indexed from, address indexed to, uint amount);
  event BurnDyad (uint indexed id, uint amount);

  uint public constant MIN_COLLATERIZATION_RATIO = 3e18; // 300%

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  mapping(uint => uint) public id2collateral;
  mapping(uint => uint) public id2dyad;

  Nft           public dNft;
  Dyad          public dyad;
  IAggregatorV3 public oracle;

  modifier isNftOwner(uint id) {
    if (dNft.ownerOf(id) != msg.sender) revert NotOwner(); _;
  }
  modifier isValidNft(uint id) {
    if (id >= dNft.totalSupply()) revert InvalidNft(); _;
  }
  modifier isNftOwnerOrHasPermission(uint id) {
    if (!dNft.hasPermission(id, msg.sender)) revert MissingPermission() ; _;
  }

  constructor(
      string memory _name,  
      string memory _symbol,  
      address _dNft, 
      address _dyad,
      address _oracle 
  ) {
      dNft   = Nft(_dNft);
      dyad   = Dyad(_dyad);
      oracle = IAggregatorV3(_oracle);
  }

  function deposit(uint id) 
    external 
    payable
      isValidNft(id) 
  {
    id2collateral[id] += msg.value;
    emit Deposit(id, msg.value);
  }

  function withdraw(uint from, address to, uint amount) 
    external 
      isNftOwnerOrHasPermission(from) 
    {
      id2collateral[from] -= amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      to.safeTransferETH(amount); // re-entrancy
      emit Withdraw(from, to, amount);
  }

  /// @inheritdoc IDNft
  function mintDyad(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
    {
      id2dyad[from] += amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      dyad.mint(to, amount);
      emit MintDyad(from, to, amount);
  }

  function burnDyad(uint id, uint amount) 
    external 
  {
    dyad.burn(msg.sender, amount);
    id2dyad[id] -= amount;
    emit BurnDyad(id, amount);
  }

  function liquidate(uint id, address to) 
    external 
    payable {
      if (_collatRatio(id) >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh(); 
      id2collateral[id] += msg.value;
      if (_collatRatio(id) <  MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      _transfer(ownerOf(id), to, id);
      emit Liquidate(id, to);
  }

  function redeem(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
    returns (uint) { 
      dyad.burn(msg.sender, amount);
      id2dyad[from] -= amount;
      uint eth       = amount*1e8 / _getEthPrice();
      id2collateral[from]  -= eth;
      to.safeTransferETH(eth); // re-entrancy 
      emit Redeem(from, amount, to, eth);
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
      return (id2collateral[id] * _getEthPrice()/1e8).divWadDown(_dyad);
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

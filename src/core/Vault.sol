// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IDNft} from "../interfaces/IDNft.sol";
import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";
import {Nft} from "./Nft.sol";

contract Vault {
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

  mapping(uint => uint) public id2collateral;
  mapping(uint => uint) public id2dyad;

  Nft           public dNft;
  Dyad          public dyad;
  IERC20        public collateral;
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
      address _dNft, 
      address _dyad,
      address _collateral,
      address _oracle 
  ) {
      dNft       = Nft(_dNft);
      dyad       = Dyad(_dyad);
      collateral = IERC20(_collateral);
      oracle     = IAggregatorV3(_oracle);
  }

  function deposit(uint id, uint amount) 
    external 
      isValidNft(id) 
  {
    collateral.transferFrom(msg.sender, address(this), amount);
    id2collateral[id] += amount;
    emit Deposit(id, amount);
  }

  function withdraw(uint from, address to, uint amount) 
    external 
      isNftOwnerOrHasPermission(from) 
    {
      id2collateral[from] -= amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      collateral.transfer(to, amount);
      emit Withdraw(from, to, amount);
  }

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

  function liquidate(uint id, address to, uint amount) 
    external {
      if (_collatRatio(id) >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh(); 
      id2collateral[id] += amount;
      if (_collatRatio(id) <  MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      dNft.liquidate(id, to);
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
      collateral.transfer(to, amount);
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

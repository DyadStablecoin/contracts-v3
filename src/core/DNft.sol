// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {IDNft} from "../interfaces/IDNft.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionManager} from "./PermissionManager.sol";

contract DNft is IDNft, ERC721Enumerable, PermissionManager {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant  MIN_COLLATERIZATION_RATIO = 3e18;     // 300%
  uint public constant  LIQUIDATION_THRESHLD      = 0.001e18; // 0.001%
  uint public immutable MAX_SUPPLY;            // Max supply of DNfts
  uint public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft

  uint public ethPrice;
  uint public totalDeposit; // Sum of all deposits
  uint public totalShares;  // Sum of all shares

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  mapping(uint => uint) public id2Shares;

  modifier isOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
  }
  modifier isOwnerOrHasPermission(uint id, Permission permission) {
    if (
      ownerOf(id) != msg.sender && 
      !hasPermission(id, msg.sender, permission)
    ) revert MissingPermission(); 
    _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      uint    _maxSupply,
      uint    _minMintDyadDeposit, 
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MAX_SUPPLY            = _maxSupply;
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;
      ethPrice              = _getEthPrice();

      for (uint i = 0; i < _insiders.length; i++) {
        _mintNft(_insiders[i]); // insiders do not require a DYAD deposit
      }
  }

  // Mint new DNft to `to` 
  function mint(address to)
    external 
    payable 
    returns (uint) {
      uint newDeposit = _eth2dyad(msg.value);
      if (newDeposit < MIN_MINT_DYAD_DEPOSIT) { revert DepositTooLow(); }
      uint id = _mintNft(to); 
      _addShares(id, newDeposit);
      return id;
  }

  // Mint new DNft to `to`
  function _mintNft(address to)
    private 
    returns (uint) {
      uint id = totalSupply();
      if (id >= MAX_SUPPLY) { revert MaxSupply(); }
      _mint(to, id); // will revert if `to` == address(0)
      emit Minted(to, id);
      return id;
  }

  // Deposit ETH
  function deposit(uint id) 
    external 
      isOwnerOrHasPermission(id, Permission.DEPOSIT)
    payable
    returns (uint) {
      uint newDeposit = _eth2dyad(msg.value);
      _addShares(id, newDeposit);
      return newDeposit;
  }

  // Move `shares` `from` one dNFT `to` another dNFT
  function move(uint from, uint to, uint shares) 
    external 
      isOwnerOrHasPermission(from, Permission.MOVE) 
    {
      id2Shares[from] -= shares;
      id2Shares[to]   += shares;
      emit Moved(from, to, shares);
  }

  function rebase() external {
      uint newEthPrice = _getEthPrice();
      bool rebaseUp    = newEthPrice > ethPrice;
      uint priceChange = rebaseUp ? (newEthPrice - ethPrice).divWadDown(ethPrice)
                                  : (ethPrice - newEthPrice).divWadDown(ethPrice);
      uint dyadDelta   = (dyad.totalSupply()+totalDeposit).mulWadDown(priceChange);
      rebaseUp ? totalDeposit += dyadDelta
               : totalDeposit -= dyadDelta;
      ethPrice = newEthPrice; 
      emit Rebased();
  }

  // Withdraw `amount` of deposited DYAD as an ERC-20 token from a dNFT
  function withdraw(uint from, address to, uint _deposit)
    external 
      isOwnerOrHasPermission(from, Permission.WITHDRAW)
    returns (uint) {
      _subShares(from, _deposit);
      uint collatVault    = address(this).balance * _getEthPrice()/1e8;
      uint newCollatRatio = collatVault.divWadDown(dyad.totalSupply() + _deposit);
      if (newCollatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(); }
      emit Withdrawn(from, to, _deposit);
      return newCollatRatio;
  }

  // Redeem DYAD for ETH
  function redeemDyad(uint from, address to, uint _dyad)
    external 
      isOwnerOrHasPermission(from, Permission.REDEEM_DYAD)
    returns (uint) { 
      dyad.burn(msg.sender, _dyad);
      uint eth = _dyad*1e8 / _getEthPrice();
      to.safeTransferETH(eth); // re-entrancy vector
      emit Redeemed(from, _dyad, to, eth);
      return eth;
  }

  // Redeem deposit for ETH
  function redeemDeposit(uint from, address to, uint _deposit)
    external 
      isOwnerOrHasPermission(from, Permission.REDEEM_DEPOSIT)
    returns (uint) { 
      _subShares(from, _deposit);
      uint eth = _deposit*1e8 / _getEthPrice();
      to.safeTransferETH(eth); // re-entrancy vector
      emit Redeemed(from, _deposit, to, eth);
      return eth;
  }

  // Liquidate DNft 
  function liquidate(uint id, address to) 
    external 
    payable {
      uint shares    = id2Shares[id];
      uint threshold = totalShares.mulWadDown(LIQUIDATION_THRESHLD);
      if (shares > threshold) { revert NotLiquidatable(); }
      uint newDeposit = _eth2dyad(msg.value);
      uint newShares  = _addShares(id, newDeposit);
      if (shares + newShares <= threshold) { revert MissingShares(); }
      emit Liquidated(to, id); 
  }

  function grant(uint id, PermissionSet[] calldata permissionSets) 
    external 
      isOwner(id) 
    {
      _grant(id, permissionSets);
  }

  function _addShares(uint id, uint _deposit)
    private
    returns (uint) {
      uint shares    = _deposit2shares(_deposit);
      id2Shares[id] += shares;
      totalDeposit  += _deposit;
      totalShares   += shares;
      emit AddedShares(id, shares);
      return shares;
  }

  function _subShares(uint id, uint _deposit)
    private
    returns (uint) {
      uint shares    = _deposit2shares(_deposit);
      id2Shares[id] -= shares;
      totalDeposit  -= _deposit;
      totalShares   -= shares;
      emit RemovedShares(id, shares);
      return shares;
  }

  // Return the value of `eth` in DYAD
  function _eth2dyad(uint eth) 
    private 
    view 
    returns (uint) {
      return eth * _getEthPrice() / 1e8; 
  }

  function _deposit2shares(uint _deposit) 
    private 
    view 
    returns (uint) {
      if (totalShares == 0) { return _deposit; }
      // (deposit * totalShares) / totalDeposit
      return _deposit.mulWadDown(totalShares).divWadDown(totalDeposit);
  }

  function _shares2deposit(uint shares) 
    private
    view 
    returns (uint) {
      // (shares * totalDeposit) / totalShares
      return shares.mulWadDown(totalDeposit).divWadDown(totalShares);
  }

  // ETH price in USD
  function _getEthPrice() 
    private 
    view 
    returns (uint) {
      ( , int price, , , ) = oracle.latestRoundData();
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
      id2LastOwnershipChange[id] = block.number;
  }
}

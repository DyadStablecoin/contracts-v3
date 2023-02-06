// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {IDNft} from "../interfaces/IDNft.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionManager} from "./PermissionManager.sol";

contract DNft is IDNft, ERC721Enumerable, PermissionManager, Owned {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant  INSIDER_MINTS             = 300; 
  uint public constant  PUBLIC_MINTS              = 1700; 
  uint public constant  MIN_COLLATERIZATION_RATIO = 3e18;     // 300%
  uint public constant  LIQUIDATION_THRESHLD      = 0.001e18; // 0.1%
  uint public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft

  uint public ethPrice;
  uint public totalDeposit; // Sum of all deposits
  uint public totalShares;  // Sum of all shares

  uint public insiderMints;
  uint public publicMints;

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  mapping(uint => uint) public id2Shares;
  mapping(uint => bool) public id2Locked;
  mapping(uint => uint) public id2LastDeposit; // id => (blockNumber)

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
  modifier isLocked(uint id) {
    if (!id2Locked[id]) revert NotLocked(); _;
  }
  modifier isNotLocked(uint id) {
    if (id2Locked[id]) revert Locked(); _;
  }

  constructor(
      address _dyad,
      address _oracle, 
      uint    _minMintDyadDeposit, 
      address _owner
  ) ERC721("Dyad NFT", "dNFT") 
    Owned(_owner) {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;
      ethPrice              = _getEthPrice();
  }

  /// @inheritdoc IDNft
  function mint(address to)
    external 
    payable 
    returns (uint) {
      if (++publicMints > PUBLIC_MINTS) revert PublicMintsExceeded();
      uint id         = _mintNft(to); 
      uint newDeposit = _deposit(id);
      if (newDeposit < MIN_MINT_DYAD_DEPOSIT) revert DepositTooLow();
      return id;
  }

  /// @inheritdoc IDNft
  function _mint(address to)
    external 
    payable 
      onlyOwner
    returns (uint) {
      if (++insiderMints > INSIDER_MINTS) revert InsiderMintsExceeded();
      uint id = _mintNft(to);
      id2Locked[id] = true;
      return id; 
  }

  // Mint new DNft to `to`
  function _mintNft(address to)
    private 
    returns (uint) {
      uint id = totalSupply();
      _mint(to, id); // will revert if `to` == address(0)
      emit Minted(to, id);
      return id;
  }

  /// @inheritdoc IDNft
  function deposit(uint id) 
    public 
      isOwnerOrHasPermission(id, Permission.DEPOSIT)
    payable
    returns (uint) {
      id2LastDeposit[id] = block.number;
      return _deposit(id);
  }

  function _deposit(uint id) 
    private 
    returns (uint) {
      uint newDeposit = _eth2dyad(msg.value);
      _addShares(id, newDeposit);
      return newDeposit;
  }

  /// @inheritdoc IDNft
  function move(uint from, uint to, uint shares) 
    external 
      isOwnerOrHasPermission(from, Permission.MOVE) 
    {
      id2Shares[from] -= shares;
      id2Shares[to]   += shares;
      emit Moved(from, to, shares);
  }

  /// @inheritdoc IDNft
  function rebase() 
    external 
    returns (uint) {
      uint newEthPrice = _getEthPrice();
      if (newEthPrice == ethPrice) revert SamePrice();
      bool rebaseUp    = newEthPrice > ethPrice;
      uint priceChange = rebaseUp ? (newEthPrice - ethPrice).divWadDown(ethPrice)
                                  : (ethPrice - newEthPrice).divWadDown(ethPrice);
      uint supplyDelta = (dyad.totalSupply()+totalDeposit).mulWadDown(priceChange);
      rebaseUp ? totalDeposit += supplyDelta
               : totalDeposit -= supplyDelta;
      ethPrice = newEthPrice; 
      emit Rebased(supplyDelta);
      return supplyDelta;
  }

  /// @inheritdoc IDNft
  function withdraw(uint from, address to, uint amount)
    external 
      isOwnerOrHasPermission(from, Permission.WITHDRAW)
      isNotLocked(from)
    returns (uint) {
      if (id2LastDeposit[from] == block.number) { revert DepositedInSameBlock(); } 
      _subShares(from, amount); // fails if `from` doesn't have enough shares
      uint collatVault    = address(this).balance * _getEthPrice()/1e8;
      uint newCollatRatio = collatVault.divWadDown(dyad.totalSupply() + amount);
      if (newCollatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(); }
      dyad.mint(to, amount);
      emit Withdrawn(from, to, amount);
      return newCollatRatio;
  }

  // Redeem DYAD ERC20 for ETH
  function redeemDyad(address to, uint _dyad)
    external 
    returns (uint) { 
      dyad.burn(msg.sender, _dyad); // reverts if `from` doesn't have enough DYAD
      uint eth = _dyad2eth(_dyad);
      to.safeTransferETH(eth);      // re-entrancy vector
      emit RedeemedDyad(msg.sender, _dyad, to, eth);
      return eth;
  }

  // Redeem deposit for ETH
  function redeemDeposit(uint from, address to, uint amount)
    external 
      isOwnerOrHasPermission(from, Permission.REDEEM_DEPOSIT)
      isNotLocked(from)
    returns (uint) { 
      _subShares(from, amount); // fails if `from` doesn't have enough shares
      uint eth = _dyad2eth(amount);
      to.safeTransferETH(eth); // re-entrancy vector
      emit RedeemedDeposit(from, amount, to, eth);
      return eth;
  }

  // Liquidate DNft 
  function liquidate(uint id, address to) 
    external 
      isNotLocked(id)
    payable {
      uint shares    = id2Shares[id];
      uint threshold = totalShares.mulWadDown(LIQUIDATION_THRESHLD);
      if (shares > threshold) { revert NotLiquidatable(); }
      uint newDeposit = _eth2dyad(msg.value);
      uint newShares  = _addShares(id, newDeposit);
      if (shares + newShares <= threshold) { revert MissingShares(); }
      _transfer(ownerOf(id), to, id);
      emit Liquidated(to, id); 
  }

  function grant(uint id, PermissionSet[] calldata permissionSets) 
    external 
      isOwner(id) 
    {
      _grant(id, permissionSets);
  }

  function unlock(uint id) 
    external
      isOwner(id)
      isLocked(id)
    {
      id2Locked[id] = false;
  }

  function _addShares(uint id, uint amount)
    private
    returns (uint) {
      uint shares    = _deposit2shares(amount);
      id2Shares[id] += shares;
      totalDeposit  += amount;
      totalShares   += shares;
      emit AddedShares(id, shares);
      return shares;
  }

  function _subShares(uint id, uint amount)
    private
    returns (uint) {
      uint shares    = _deposit2shares(amount);
      id2Shares[id] -= shares;
      totalDeposit  -= amount;
      totalShares   -= shares;
      emit RemovedShares(id, shares);
      return shares;
  }

  // Return the value of `eth` in DYAD
  function _eth2dyad(uint eth) 
    private 
    view 
    returns (uint) {
      return eth * _getEthPrice()/1e8; 
  }

  function _dyad2eth(uint _dyad)
    private 
    view 
    returns (uint) {
      return _dyad*1e8 / _getEthPrice();
  }

  function _deposit2shares(uint amount) 
    private 
    view 
    returns (uint) {
      if (totalShares == 0) { return amount; }
      return amount.mulWadDown(totalShares).divWadDown(totalDeposit);
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
      id2LastOwnershipChange[id] = block.number; // resets permissions on transfer
  }
}

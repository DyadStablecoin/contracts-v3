// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {IDNft} from "../interfaces/IDNft.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionManager} from "./PermissionManager.sol";

contract DNft is ERC721Enumerable, PermissionManager, Owned, IDNft {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant  INSIDER_MINTS             = 300; 
  uint public constant  PUBLIC_MINTS              = 1700; 
  uint public constant  MIN_COLLATERIZATION_RATIO = 3e18;     // 300%
  uint public constant  LIQUIDATION_THRESHLD      = 0.001e18; // 0.1%
  uint public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft

  uint public ethPrice;     // ETH price from the last `rebase`
  uint public totalDeposit; // Sum of all deposits
  uint public totalShares;  // Sum of all shares

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  mapping(uint => uint) public id2Shares; // dNFT deposit is stored in shares
  mapping(uint => bool) public id2Locked; // insider dNFT is locked after mint

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  modifier isNftOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
  }
  modifier isNftOwnerOrHasPermission(uint id, Permission permission) {
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
    external 
    payable
    returns (uint) 
  {
    return _deposit(id);
  }

  function _deposit(uint id) 
    private 
    returns (uint) {
      uint newDeposit = _eth2dyad(msg.value);
      _addDeposit(id, newDeposit);
      return newDeposit;
  }

  /// @inheritdoc IDNft
  function move(uint from, uint to, uint shares) 
    external 
      isNftOwnerOrHasPermission(from, Permission.MOVE) 
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
      isNftOwnerOrHasPermission(from, Permission.WITHDRAW)
      isNotLocked(from)
    returns (uint) {
      _subDeposit(from, amount); // fails if `from` doesn't have enough deposit shares
      uint collatVault    = address(this).balance * _getEthPrice()/1e8;
      uint newCollatRatio = collatVault.divWadDown(dyad.totalSupply() + amount);
      if (newCollatRatio < MIN_COLLATERIZATION_RATIO) { revert CrTooLow(); }
      dyad.mint(to, amount);
      emit Withdrawn(from, to, amount);
      return newCollatRatio;
  }

  /// @inheritdoc IDNft
  function redeemDyad(address to, uint amount)
    external 
    returns (uint) { 
      dyad.burn(msg.sender, amount); 
      return _redeem(to, amount);
  }

  /// @inheritdoc IDNft
  function redeemDeposit(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from, Permission.REDEEM)
      isNotLocked(from)
    returns (uint) { 
      _subDeposit(from, amount); 
      return _redeem(to, amount);
  }

  // Redeem `amount` of DYAD to `to`
  function _redeem(address to, uint amount)
    private 
    returns (uint) { 
      uint eth = _dyad2eth(amount);
      emit Redeemed(msg.sender, amount, to, eth);
      to.safeTransferETH(eth); // re-entrancy vector
      return eth;
  }

  /// @inheritdoc IDNft
  function liquidate(uint id, address to) 
    external 
      isNotLocked(id)
    payable {
      uint shares    = id2Shares[id];
      uint threshold = totalShares.mulWadDown(LIQUIDATION_THRESHLD);
      if (shares > threshold) { revert NotLiquidatable(); }
      uint newShares  = _addDeposit(id, _eth2dyad(msg.value)); 
      if (shares + newShares <= threshold) { revert MissingShares(); }
      _transfer(ownerOf(id), to, id);
      emit Liquidated(to, id); 
  }

  /// @inheritdoc IDNft
  function grant(uint id, PermissionSet[] calldata permissionSets) 
    external 
      isNftOwner(id) 
    {
      _grant(id, permissionSets);
  }

  /// @inheritdoc IDNft
  function unlock(uint id) 
    external
      isNftOwner(id)
      isLocked(id)
    {
      id2Locked[id] = false;
      emit Unlocked(id);
  }

  function _addDeposit(uint id, uint amount)
    private
    returns (uint) {
      uint shares    = _deposit2Shares(amount);
      id2Shares[id] += shares;
      totalShares   += shares;
      totalDeposit  += amount;
      emit AddedShares(id, shares);
      return shares;
  }

  function _subDeposit(uint id, uint amount)
    private {
      uint shares    = _deposit2Shares(amount);
      id2Shares[id] -= shares;
      totalShares   -= shares;
      totalDeposit  -= amount;
      emit RemovedShares(id, shares);
  }

  // Convert `amount` of deposit to the shares it represents
  function _deposit2Shares(uint amount) 
    private 
    view 
    returns (uint) {
      uint _totalShares = totalShares; // Saves one SLOAD if totalShares is non-zero
      if (_totalShares == 0) { return amount; }
      uint shares = amount.mulDivDown(_totalShares, totalDeposit);
      if (shares == 0) { revert ZeroShares(); } // Check rounding down error 
      return shares;
  }

  // Return the value of ETH in DYAD
  function _eth2dyad(uint eth) 
    private 
    view 
    returns (uint) {
      return eth * _getEthPrice()/1e8; 
  }

  // Return the value of DYAD in ETH
  function _dyad2eth(uint _dyad)
    private 
    view 
    returns (uint) {
      return _dyad*1e8 / _getEthPrice();
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

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

contract DNft is ERC721Enumerable, Owned, IDNft {
  using SafeTransferLib   for address;
  using SafeCast          for int256;
  using FixedPointMathLib for uint256;

  uint public constant  INSIDER_MINTS             = 300; 
  uint public constant  PUBLIC_MINTS              = 1700; 
  uint public constant  MIN_COLLATERIZATION_RATIO = 3e18; // 300%
  uint public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft
  uint public immutable MIN_DYAD_DEPOSIT;

  uint public ethPrice;     // ETH price from the last `rebase`
  uint public totalDeposit; // Sum of all deposits
  uint public totalShares;  // Sum of all shares

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  struct Permission {
    bool    hasPermission; 
    uint248 lastUpdated;
  }

  mapping(uint => uint) public id2shares;              // dNFT deposit in shares
  mapping(uint => uint) public id2withdrawn;           // dNFT DYAD withdrawals 
  mapping(uint => uint) public id2lastDeposit;         // id => blockNumber
  mapping(uint => uint) public id2lastOwnershipChange; // id => blockNumber
  mapping(uint => mapping (address => Permission)) public id2permission; // id => (operator => Permission)

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  modifier isNftOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
  }
  modifier isNftOwnerOrHasPermission(uint id) {
    if (!hasPermission(id, msg.sender)) revert MissingPermission() ; _;
  }
  modifier isValidNft(uint id) {
    if (id >= totalSupply()) revert InvalidNft(); _;
  }
  modifier rebase() { // Rebase DYAD total supply to reflect the latest price changes
    uint newEthPrice = _getEthPrice();
    if (newEthPrice != ethPrice) {
      bool rebaseUp    = newEthPrice > ethPrice;
      uint priceChange = rebaseUp ? (newEthPrice - ethPrice).divWadDown(ethPrice)
                                  : (ethPrice - newEthPrice).divWadDown(ethPrice);
      uint supplyDelta = (dyad.totalSupply()+totalDeposit).mulWadDown(priceChange);
      rebaseUp ? totalDeposit += supplyDelta
               : totalDeposit -= supplyDelta;
      ethPrice = newEthPrice; 
      emit Rebased(supplyDelta);
    }
    _;
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
      MIN_DYAD_DEPOSIT      = _minMintDyadDeposit.mulWadDown(0.1e18);
      ethPrice              = _getEthPrice();
  }

  /// @inheritdoc IDNft
  function mint(address to)
    external 
      rebase
    payable 
    returns (uint) {
      if (++publicMints > PUBLIC_MINTS) revert PublicMintsExceeded();
      uint id     = _mintNft(to);
      uint shares = _depositEth(id);
      if (_shares2deposit(shares) < MIN_MINT_DYAD_DEPOSIT) revert DepositTooLow();
      return id;
  }

  /// @inheritdoc IDNft
  function _mint(address to)
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
      emit Minted(to, id);
      return id;
  }

  /// @inheritdoc IDNft
  function depositEth(uint id) 
    external 
      isNftOwnerOrHasPermission(id) 
      rebase
    payable
    returns (uint) 
  {
    return _depositEth(id);
  }

  function _depositEth(uint id) 
    private 
    returns (uint) {
      return _addDeposit(id, _eth2dyad(msg.value));
  }

  /// @inheritdoc IDNft
  function depositDyad(uint id, uint amount) 
    external 
      isNftOwnerOrHasPermission(id) 
      rebase
    returns (uint) {
      _burnDyad(id, amount);
      return _addDeposit(id, amount);
  }

  /// @inheritdoc IDNft
  function move(uint from, uint to, uint shares) 
    external 
      isNftOwnerOrHasPermission(from) 
      isValidNft(to)
    {
      id2shares[from] -= shares;
      id2shares[to]   += shares;
      emit Moved(from, to, shares);
  }

  /// @inheritdoc IDNft
  function withdraw(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
      rebase
    {
      if (id2lastDeposit[from] + 10 > block.number) revert TooEarly();
      _subDeposit(from, amount); 
      id2withdrawn[from] += amount;
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      dyad.mint(to, amount);
      emit Withdrawn(from, to, amount);
  }

  /// @inheritdoc IDNft
  function redeemDyad(uint from, address to, uint amount)
    external 
      isValidNft(from)
      rebase
    returns (uint) { 
      _burnDyad(from, amount);
      return _redeem(from, to, amount);
  }

  function _burnDyad(uint from, uint amount)
    private {
      id2withdrawn[from] -= amount;
      dyad.burn(msg.sender, amount); 
  }

  /// @inheritdoc IDNft
  function redeemDeposit(uint from, address to, uint amount)
    external 
      isNftOwnerOrHasPermission(from)
      rebase
    returns (uint) { 
      _subDeposit(from, amount); 
      if (_shares2deposit(id2shares[from]) < MIN_DYAD_DEPOSIT) revert DepositTooLow();
      if (_collatRatio(from) < MIN_COLLATERIZATION_RATIO)      revert CrTooLow(); 
      return _redeem(from, to, amount);
  }

  // Redeem `amount` of DYAD to `to`
  function _redeem(uint from, address to, uint amount)
    private 
    returns (uint) { 
      if (id2lastDeposit[from] + 10 > block.number) revert TooEarly();
      uint eth = _dyad2eth(amount);
      emit Redeemed(msg.sender, amount, to, eth);
      to.safeTransferETH(eth); // re-entrancy 
      return eth;
  }

  /// @inheritdoc IDNft
  function liquidate(uint id, address to) 
    external 
      rebase
    payable {
      if (_collatRatio(id) >= MIN_COLLATERIZATION_RATIO) revert CrTooHigh(); 
      _addDeposit(id, _eth2dyad(msg.value)); 
      if (_collatRatio(id) <  MIN_COLLATERIZATION_RATIO) revert CrTooLow(); 
      address owner = ownerOf(id); // save gas
      _transfer(owner, to, id);
      emit Liquidated(owner, to, id); 
  }

  /// @inheritdoc IDNft
  function grant(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      id2permission[id][operator] = Permission(true, uint248(block.number));
      emit Granted(id, operator);
  }

  /// @inheritdoc IDNft
  function revoke(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      delete id2permission[id][operator];
      emit Revoked(id, operator);
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
      uint withdrawn = id2withdrawn[id]; // save gas
      if (withdrawn == 0) return type(uint).max;
      // cr = deposit / withdrawn
      return _shares2deposit(id2shares[id]).divWadDown(withdrawn);
  }

  function _addDeposit(uint id, uint amount)
    private
    returns (uint) {
      id2lastDeposit[id] = block.number;
      uint shares    = _deposit2shares(amount);
      id2shares[id] += shares;
      totalShares   += shares;
      totalDeposit  += amount;
      emit Added(id, shares);
      return shares;
  }

  function _subDeposit(uint id, uint amount)
    private {
      uint shares    = _deposit2shares(amount);
      id2shares[id] -= shares;
      totalShares   -= shares;
      totalDeposit  -= amount;
      emit Removed(id, shares);
  }

  // Convert `amount` of deposit to the shares it represents
  function _deposit2shares(uint amount) 
    private 
    view
    returns (uint) {
      uint _totalShares = totalShares; // Saves one SLOAD if totalShares is non-zero
      if (_totalShares == 0) { return amount; }
      uint shares = amount.mulDivDown(_totalShares, totalDeposit);
      if (shares == 0) { revert ZeroShares(); } // Check rounding down error 
      return shares;
  }

  // Convert `amount` of deposit to the shares it represents
  function _shares2deposit(uint shares) 
    private 
    view 
    returns (uint) {
      uint _totalShares = totalShares; // Saves one SLOAD if totalShares is non-zero
      if (_totalShares == 0) { return shares; }
      uint deposit = shares.mulDivDown(totalDeposit, totalShares);
      if (deposit == 0) { revert ZeroDeposit(); } // Check rounding down error 
      return deposit;
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

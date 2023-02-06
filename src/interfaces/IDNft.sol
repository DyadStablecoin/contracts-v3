// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  event AddedShares    (uint indexed id, uint amount);
  event RemovedShares  (uint indexed id, uint amount);
  event Minted         (address indexed to, uint indexed id);
  event Liquidated     (address indexed to, uint indexed id);
  event RedeemedDyad   (address indexed from, uint dyad, address indexed to, uint eth);
  event RedeemedDeposit(uint indexed from, uint dyad, address indexed to, uint eth);
  event Moved          (uint indexed from, uint indexed to, uint amount);
  event Withdrawn      (uint indexed from, address indexed to, uint amount);
  event Rebased        (uint supplyDelta);

  error InsiderMintsExceeded();
  error PublicMintsExceeded ();
  error SamePrice         ();
  error DepositTooLow     ();
  error NotLiquidatable   ();
  error MissingShares     ();
  error InsufficientShares();
  error CrTooLow          ();
  error Locked            ();
  error NotLocked         ();

  /**
   * @notice Mint a new dNFT to `to`
   * @dev Will revert:
   *      - If the public mints max has been reached
   *      - If `msg.value` is not enough to cover the deposit minimum
   *      - If `to` is the zero address
   * @dev Emits:
   *      - Minted
   *      - DyadMinted
   * @dev For Auditors:
   *      - To save gas it does not check if `msg.value` is zero 
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function mint(address to) external payable returns (uint id);
}

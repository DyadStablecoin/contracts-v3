// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  event AddedShares  (uint indexed id, uint amount);
  event RemovedShares(uint indexed id, uint amount);
  event Minted     (address indexed to, uint indexed id);
  event Redeemed   (uint indexed from, uint dyad, address indexed to, uint eth);
  event Moved      (uint indexed from, uint indexed to, uint amount);
  event Liquidated (address indexed to, uint indexed id);
  event Withdrawn  (uint indexed from, address indexed to, uint amount);
  event Rebased    (uint supplyDelta);

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
}

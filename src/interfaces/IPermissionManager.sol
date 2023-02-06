// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPermissionManager {
  enum Permission { DEPOSIT, MOVE, WITHDRAW, REDEEM_DEPOSIT }

  error MissingPermission();
  error NotOwner         ();

  event Modified(uint indexed id, PermissionSet[] permissions);

  struct PermissionSet {
    address operator;         // The address of the operator
    Permission[] permissions; // The permissions given to the operator
  }

  struct NftPermission {
    uint8   permissions;
    uint248 lastUpdated; // The block number when it was last updated
  }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPermissionManager {
  enum Permission { MOVE, WITHDRAW, REDEEM }

  error MissingPermission();
  error NotOwner         ();

  event Modified(uint indexed id, OperatorPermission[] operatorPermission);

  struct OperatorPermission {
    Permission[] permissions; // The permissions given to the operator
    address operator;         // The address of the operator
  }

  struct NftPermission {
    uint8   permissions;
    uint248 lastUpdated; // The block number when it was last updated
  }
}

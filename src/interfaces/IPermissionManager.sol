// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPermissionManager {
  enum Permission { MOVE, WITHDRAW, REDEEM }

  error MissingPermission();
  error NotOwner         ();

  event Modified(uint indexed id, OperatorPermission[] operatorPermission);

  struct OperatorPermission {
    Permission[] permissions; // Permissions given to the operator
    address operator;
  }

  struct NftPermission {
    uint8   permissions; // Bit map of the permissions
    uint248 lastUpdated; // The block number of the last permissions update
  }
}

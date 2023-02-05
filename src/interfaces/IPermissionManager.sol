// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

interface IPermissionManager {
  enum Permission { DEPOSIT, REDEEM_DYAD, REDEEM_DEPOSIT, MOVE, WITHDRAW }

  error MissingPermission();

  struct PermissionSet {
    address operator;         // The address of the operator
    Permission[] permissions; // The permissions given to the operator
  }

  struct NftPermission {
    uint8   permissions;
    uint248 lastUpdated; // The block number when it was last updated
  }
}

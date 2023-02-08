// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {PermissionMath} from "../libraries/PermissionMath.sol";

contract PermissionManager is IPermissionManager {
  using PermissionMath for Permission[];
  using PermissionMath for uint8;

  // id => blockNumber
  mapping(uint => uint)                              public id2LastOwnershipChange;
  // id => (operator => NftPermission)
  mapping(uint => mapping(address => NftPermission)) public id2NftPermission; 

  // Grant or revoke permissions
  function _grant(uint id, OperatorPermission[] calldata operatorPermissions) 
    internal {
      for (uint i = 0; i < operatorPermissions.length; ) {
        OperatorPermission memory operatorPermission = operatorPermissions[i];
        if (operatorPermission.permissions.length == 0) {
          delete id2NftPermission[id][operatorPermission.operator]; // revoke permissions
        } else {
          id2NftPermission[id][operatorPermission.operator] = NftPermission(
            operatorPermission.permissions._toUInt8(),
            uint248(block.number)
          );
        }
        unchecked { ++i; }
      }
      emit Granted(id, operatorPermissions);
  }

  /// @inheritdoc IPermissionManager
  function hasPermission(uint id, address operator, Permission permission) 
    public 
    view 
    returns (bool) {
      NftPermission memory nftPermission = id2NftPermission[id][operator];
      return nftPermission.permissions._hasPermission(permission) &&
        id2LastOwnershipChange[id] < nftPermission.lastUpdated;
  }
}

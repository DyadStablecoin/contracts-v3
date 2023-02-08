// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {PermissionMath} from "../libraries/PermissionMath.sol";

contract PermissionManager is IPermissionManager {
  using PermissionMath for Permission[];
  using PermissionMath for uint8;

  mapping(uint => uint) /* id => block number */     public id2LastOwnershipChange;
  mapping(uint => mapping(address => NftPermission)) public id2NftPermission; 

  // Grant or revoke permissions
  function _grant(uint id, OperatorPermission[] calldata OperatorPermissions) 
    internal {
      uint248 blockNumber = uint248(block.number);
      for (uint i = 0; i < OperatorPermissions.length; ) {
        OperatorPermission memory _permissionSet = OperatorPermissions[i];
        if (_permissionSet.permissions.length == 0) {
          delete id2NftPermission[id][_permissionSet.operator];
        } else {
          id2NftPermission[id][_permissionSet.operator] = NftPermission(
            _permissionSet.permissions._toUInt8(),
            blockNumber
          );
        }
        unchecked { ++i; }
      }
      emit Modified(id, OperatorPermissions);
  }

  // Check if operator has permission for dNFT with id
  function hasPermission(uint id, address operator, Permission permission) 
    public 
    view 
    returns (bool) {
      NftPermission memory _nftPermission = id2NftPermission[id][operator];
      return _nftPermission.permissions._hasPermission(permission) &&
        // If there was an ownership change after the permission was last updated,
        // then the operator doesn't have the permission
        id2LastOwnershipChange[id] < _nftPermission.lastUpdated;
  }
}

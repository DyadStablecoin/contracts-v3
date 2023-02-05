// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPermissionManager} from "../interfaces/IPermissionManager.sol";
import {PermissionMath} from "../libraries/PermissionMath.sol";

contract PermissionManager is IPermissionManager {
  using PermissionMath for Permission[];
  using PermissionMath for uint8;

  mapping(uint => uint)                              public id2LastOwnershipChange;
  mapping(uint => mapping(address => NftPermission)) public id2NftPermission; 

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

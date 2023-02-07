// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPermissionManager} from "../interfaces/IPermissionManager.sol";

library PermissionMath {
  // Convert list of permissions to an int representation that contains them all
  function _toUInt8(IPermissionManager.Permission[] memory _permissions)
    internal 
    pure 
    returns (uint8 _representation) {
      for (uint256 i = 0; i < _permissions.length; ) {
        _representation |= uint8(1 << uint8(_permissions[i]));
        unchecked { ++i; }
      }
  }

  // Check if `_permission` is in the int `_representation` of a set of permissions
  function _hasPermission(
      uint8 _representation, 
      IPermissionManager.Permission _permission
  ) internal 
    pure 
    returns (bool hasPermission) {
      uint256 _bitMask = 1 << uint8(_permission);
      hasPermission = (_representation & _bitMask) != 0;
  }
}

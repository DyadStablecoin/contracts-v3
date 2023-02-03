// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {IPermissionManager} from "../interfaces/IPermissionManager.sol";

contract PermissionManager is IPermissionManager {

  function _toUInt8(Permission[] memory _permissions) 
    internal 
    pure 
    returns (uint8 _representation) {
      for (uint256 i = 0; i < _permissions.length; ) {
        _representation |= uint8(1 << uint8(_permissions[i]));
        unchecked {
          i++;
        }
      }
  }

  function _hasPermission(uint8 _representation, Permission _permission) 
    internal 
    pure 
    returns (bool hasPermission) {
      uint256 _bitMask = 1 << uint8(_permission);
      hasPermission = (_representation & _bitMask) != 0;
  }
}


// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";

library SharesMath {
  using FixedPointMathLib for uint256;

  function shares2Deposit(uint shares, uint totalDeposit, uint totalShares) 
    external 
    pure 
    returns (uint) {
      return shares.mulDivUp(totalDeposit, totalShares);
  }
}

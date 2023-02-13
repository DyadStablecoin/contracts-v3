// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC20} from "@solmate/src/tokens/ERC20.sol";

contract Kerosine is ERC20 {
  constructor() ERC20("Kerosine", "K", 18) {}
}

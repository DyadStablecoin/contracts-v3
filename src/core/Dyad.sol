// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import {ERC20Relative} from "./ERC20Relative.sol";

contract Dyad is ERC20Relative, Owned {
  constructor() ERC20Relative("DYAD Stablecoin", "DYAD") Owned(msg.sender) {}

  function mint(address to,   uint amount) public onlyOwner { _mint(to,   amount); }
  function burn(address from, uint amount) public onlyOwner { _burn(from, amount); }
}

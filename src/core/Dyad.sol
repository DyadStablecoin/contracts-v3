// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import {ERC20} from "@solmate/src/tokens/ERC20.sol";

contract Dyad is ERC20, Owned {
  constructor(
    string memory _name,
    string memory _symbol,
    address       _owner
  ) ERC20(_name, _symbol, 18) Owned(_owner) {}

  function mint(address to,   uint amount) public onlyOwner { _mint(to,   amount); }
  function burn(address from, uint amount) public onlyOwner { _burn(from, amount); }
}

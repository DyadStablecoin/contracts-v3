// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ERC20Relative is ERC20 {
  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function balanceOf(address account) 
    public 
    view
    override
    returns (uint256) 
  {
    return super.balanceOf(account) * totalSupply();
  }

}

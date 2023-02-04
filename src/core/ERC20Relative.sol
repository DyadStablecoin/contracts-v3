// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC20} from "./ERC20.sol";

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

  function _transfer(address sender, address recipient, uint256 amount) 
    internal 
    override 
  {
    super._transfer(sender, recipient, amount / totalSupply());
  }
  
  function _approve(address owner, address spender, uint256 amount) 
    internal 
    override 
  {
    super._approve(owner, spender, amount / totalSupply());
  }

  function _spendAllowance(address owner, address spender, uint256 amount) 
    internal 
    override 
  {
    super._spendAllowance(owner, spender, amount / totalSupply());
  }

  function _mint(uint256 amount) 
    internal 
  {
    _totalSupply += amount;
  }

  function _burn(uint256 amount) 
    internal 
  {
    _totalSupply -= amount;
  }

}

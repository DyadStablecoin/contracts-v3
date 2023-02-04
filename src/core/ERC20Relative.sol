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
    return super.balanceOf(account) * _totalSupply;
  }

  function _transfer(address sender, address recipient, uint256 amount) 
    internal 
    override 
  {
    super._transfer(sender, recipient, amount / _totalSupply);
  }
  
  function _approve(address owner, address spender, uint256 amount) 
    internal 
    override 
  {
    super._approve(owner, spender, amount / _totalSupply);
  }

  function _spendAllowance(address owner, address spender, uint256 amount) 
    internal 
    override 
  {
    super._spendAllowance(owner, spender, amount / _totalSupply);
  }

  function _mint(address account, uint256 amount) 
    internal 
    override
  {
    _totalSupply += amount;
    _balances[account] += (amount / _totalSupply);
    emit Transfer(address(0), account, amount);
  }

  function _burn(address account, uint256 amount) 
    internal 
    override
  {
    _totalSupply -= amount;
    _balances[account] -= (amount / _totalSupply);
    emit Transfer(account, address(0), amount);
  }

}

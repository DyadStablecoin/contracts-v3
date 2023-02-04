// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {FixedPointMathLib} from "@solmate/src/utils/FixedPointMathLib.sol";
import {ERC20} from "./ERC20.sol";

contract ERC20Relative is ERC20 {
  using FixedPointMathLib for uint256;

  constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

  function balanceOf(address account) 
    public 
    view
    override
    returns (uint) 
  {
    return super.balanceOf(account).mulWadDown(_totalSupply);
  }

  function _transfer(address sender, address recipient, uint amount) 
    internal 
    override 
  {
    super._transfer(sender, recipient, amount.divWadDown(_totalSupply));
  }
  
  function _approve(address owner, address spender, uint amount) 
    internal 
    override 
  {
    super._approve(owner, spender, amount.divWadDown(_totalSupply));
  }

  function _spendAllowance(address owner, address spender, uint amount) 
    internal 
    override 
  {
    super._spendAllowance(owner, spender, amount.divWadDown(_totalSupply));
  }

  function _mint(address account, uint amount) 
    internal 
    override
  {
    amount = amount.divWadDown(_totalSupply);
    _beforeTokenTransfer(address(0), account, amount);
    _totalSupply += amount;
    _balances[account] += amount;
    emit Transfer(address(0), account, amount);
    _afterTokenTransfer(address(0), account, amount);
  }

  function _burn(address account, uint amount) 
    internal 
    override
  {
    amount = amount.divWadDown(_totalSupply);
    _beforeTokenTransfer(account, address(0), amount);
    _totalSupply -= amount;
    _balances[account] -= amount;
    emit Transfer(account, address(0), amount);
    _afterTokenTransfer(account, address(0), amount);
  }

}

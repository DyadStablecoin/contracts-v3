// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {DNft} from "../core/DNft.sol";
import {Dyad} from "../core/Dyad.sol";
import {DyadPlus} from "../composing/DyadPlus.sol";
import {IAfterburner} from "../interfaces/IAfterburner.sol";

contract Afterburner is IAfterburner {
  DNft     dNft;
  Dyad     dyad;
  DyadPlus dyadPlus;

  mapping(uint => uint) public id2xp; 
  mapping(uint => uint) public id2credit; 
  mapping(uint => uint) public id2deposit; 
  mapping(uint => uint) public id2principal; 

  modifier isNftOwner(uint id) {
    if (dNft.ownerOf(id) != msg.sender) revert NotOwner(); _;
  }

  constructor(DNft _dNft, Dyad _dyad, DyadPlus _dyadPlus) {
    dNft     = _dNft;
    dyad     = _dyad;
    dyadPlus = _dyadPlus;
  }

  function deposit(uint id, uint amount) 
    external
      isNftOwner(id) 
    {
      dyad.transferFrom(msg.sender, address(this), amount);
      id2deposit[id] += amount;
  }

  function withdraw(uint id, address to, uint amount) 
    external
      isNftOwner(id) 
    {
    id2deposit[id] -= amount;
    dyadPlus.mint(to, amount);
  }

  function redeem(address to, uint amount) 
    external {
      dyadPlus.burn(msg.sender, amount);
      dyad.transfer(to, amount);
    }
}

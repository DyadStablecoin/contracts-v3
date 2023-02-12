// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IAfterburner {
  error NotOwner(); 

  event AddedXp(uint indexed id, uint amount);
}

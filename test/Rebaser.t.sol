// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Rebaser} from "../src/composing/Rebaser.sol";
import {SharesMath as SM} from "../src/libraries/SharesMath.sol";

contract RebaserTest is BaseTest {
  function test_Rebase() public {
    Rebaser rebaser = new Rebaser(dNft, address(oracleMock));
    uint id = dNft.mint{value: 100 ether}(address(rebaser));
    rebaser.setId(id);
    oracleMock.setPrice(900e8);
    console.log(SM.shares2Deposit(
      dNft.id2Shares(id), 
      dNft.totalDeposit(), 
      dNft.totalShares()
    ));
    // rebaser.rebase();
    dNft.rebase();
    console.log(SM.shares2Deposit(
      dNft.id2Shares(id), 
      dNft.totalDeposit(), 
      dNft.totalShares()
    ));
  }
}

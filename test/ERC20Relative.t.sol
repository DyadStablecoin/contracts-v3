// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Dyad} from "../src/core/Dyad.sol";

contract ERC20RelativeTest is Test {
  Dyad dyad;

  function setUp() public {
    dyad = new Dyad();
  }
  function test() public {
    dyad.mint(address(this), 10e18);
    dyad.mint(address(this), 10e18);
    console.log("dyad.balanceOf(address(this))", dyad.balanceOf(address(this)));
  }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {SharesMath} from "../src/libraries/SharesMath.sol";

contract DNftsTest is BaseTest {
  function test_Constructor() public {
    assertEq(dNft.owner(), MAINNET_OWNER);
    assertEq(dyad.owner(), address(dNft));
    assertTrue(address(dNft.oracle()) != address(0));
  }

  // -------------------- mintNft --------------------
  function test_mintNft() public {
    dNft.mintNft(address(this));
  }
  function testCannot_mintNft_publicMintsExceeded() public {
    for(uint i = 0; i < dNft.PUBLIC_MINTS(); i++) {
      dNft.mintNft(address(this));
    }
    vm.expectRevert();
    dNft.mintNft(address(this));
  }
  // -------------------- mintInsiderNft --------------------
  function test_mintInsiderNft() public {
    vm.prank(MAINNET_OWNER);
    dNft.mintInsiderNft(address(this));
  }
  function testCannot_mintInsiderNft_NotOwner() public {
    vm.expectRevert();
    dNft.mintInsiderNft(address(this));
  }
  function testCannot_mintInsiderNft_insiderMintsExceeded() public {
    for(uint i = 0; i < dNft.INSIDER_MINTS(); i++) {
      dNft.mintNft(address(this));
    }
    vm.expectRevert();
    dNft.mintInsiderNft(address(this));
  }
  // -------------------- deposit --------------------
  function test_deposit() public {
    uint id = dNft.mintNft(address(this));
    assertEq(dNft.id2eth(id), 0 ether);
    dNft.deposit{value: 10 ether}(id);
    assertEq(dNft.id2eth(id), 10 ether);
  }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";

contract DNftsTest is BaseTest {
  function test_Constructor() public {
    assertEq(dNft.owner(), MAINNET_OWNER);
    assertTrue(dNft.ethPrice() > 0);
  }

  // -------------------- mint --------------------
  function test_MintNft() public {
    assertEq(dNft.publicMints(), 0);
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.publicMints(), 1);
    assertEq(dNft.id2Shares(id1), 5000e18);

    uint id2 = dNft.mint{value: 6 ether}(address(this));
    assertEq(dNft.publicMints(), 2);
    assertEq(dNft.id2Shares(id2), 6000e18);
  }
  function testCannot_MintToZeroAddress() public {
    vm.expectRevert("ERC721: mint to the zero address");
    dNft.mint{value: 5 ether}(address(0));
  }
  function testCannot_MintNotReachedMinAmount() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.DepositTooLow.selector));
    dNft.mint{value: 1 ether}(address(this));
  }
  function testCannot_MintExceedsMaxAmount() public {
    assertEq(dNft.totalSupply(), 0);

    for (uint i = 0; i < dNft.PUBLIC_MINTS(); i++) {
      dNft.mint{value: 5 ether}(address(1));
    }

    vm.expectRevert(abi.encodeWithSelector(IDNft.PublicMintsExceeded.selector));
    dNft.mint{value: 5 ether}(address(1));

    assertEq(dNft.totalSupply(), dNft.PUBLIC_MINTS());
  }

  // -------------------- _mint --------------------
  function test__Mint() public {
    assertEq(dNft.insiderMints(), 0);

    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(1));

    assertEq(dNft.insiderMints(), 1);
    assertTrue(dNft.id2Locked(id));
    assertEq(dNft.id2Shares(id), 0);
  }
  function testCannot__MintOnlyOwner() public {
    vm.expectRevert("UNAUTHORIZED");
    dNft._mint(address(1));
  }
  function testCannot__MintExceedsMaxAmount() public {
    assertEq(dNft.totalSupply(), 0);

    for (uint i = 0; i < dNft.INSIDER_MINTS(); i++) {
      vm.prank(MAINNET_OWNER);
      dNft._mint(address(1));
    }

    vm.prank(MAINNET_OWNER);
    vm.expectRevert(abi.encodeWithSelector(IDNft.InsiderMintsExceeded.selector));
    dNft._mint(address(1));

    assertEq(dNft.totalSupply(), dNft.INSIDER_MINTS());
  }
  // function testCannotMintExceedsMaxSupply() public {
  //   uint nftsLeft = dNft.MAX_SUPPLY() - dNft.totalSupply();
  //   for (uint i = 0; i < nftsLeft; i++) {
  //     dNft.mint{value: 5 ether}(address(this));
  //   }
  //   // assertEq(dNft.totalSupply(), dNft.MAX_SUPPLY());
  //   vm.expectRevert(abi.encodeWithSelector(IDNft.PublicMintsExceeded.selector));
  //   dNft.mint{value: 5 ether}(address(this));
  // }

  // -------------------- rebase --------------------
  function testRebase() public {
    dNft.mint{value: 6 ether}(address(this));
    uint id2 = dNft.mint{value: 6 ether}(address(this));

    oracleMock.setPrice(1100e8);
    dNft.rebase();

    dNft.withdraw(id2, address(1), 1000e18);

    // uint id3 = dNft.mint{value: 6 ether}(address(this));
  }
}

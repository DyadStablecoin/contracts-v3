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
    assertTrue(dNft.ethPrice() > 0);
    assertTrue(address(dNft.oracle()) != address(0));
  }

  // -------------------- mint --------------------
  function test_MintNft() public {
    assertEq(dNft.publicMints(), 0);
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.publicMints(), 1);
    assertEq(dNft.id2shares(id1), 5000e18);

    uint id2 = dNft.mint{value: 6 ether}(address(this));
    assertEq(dNft.publicMints(), 2);
    assertEq(dNft.id2shares(id2), 6000e18);
  }
  function testFuzz_MintNft(uint eth) public {
    vm.assume(eth > 5 ether);
    vm.assume(eth <= address(msg.sender).balance);

    uint id = dNft.mint{value: eth}(address(this));
    assertEq(dNft.id2shares(id), eth*1000); // ETH 2 USD = $1000
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
    assertEq(dNft.id2shares(id), 0);
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
  // -------------------- depositEth --------------------
  function test_Deposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.id2shares(id), 5000e18);

    dNft.depositEth{value: 5 ether}(id);
    assertEq(dNft.id2shares(id), 10000e18);
  }
  function testFuzz_Deposit(uint eth) public {
    vm.assume(eth > 0);
    vm.assume(eth <= address(msg.sender).balance);

    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.depositEth{value: eth}(id);
  }

  // -------------------- move --------------------
  function test_Move() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    assertEq(dNft.id2shares(id1), 5000e18);
    assertEq(dNft.id2shares(id2), 5000e18);

    dNft.move(id1, id2, 1000e18);

    assertEq(dNft.id2shares(id1), 4000e18);
    assertEq(dNft.id2shares(id2), 6000e18);
  }
  function testFuzz_Move(uint eth) public {
    vm.assume(eth > 5 ether);
    vm.assume(eth <= address(msg.sender).balance/2);

    uint id1 = dNft.mint{value: eth}(address(this));
    uint id2 = dNft.mint{value: eth}(address(this));

    dNft.move(id1, id2, eth*1000);
    assertEq(dNft.id2shares(id1), 0);
    assertEq(dNft.id2shares(id2), eth*1000*2);
  }
  function testCannot_MoveIsNotOwner() public {
    uint id1 = dNft.mint{value: 5 ether}(address(1));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));
    dNft.move(id1, id2, 1000e18);
  }
  function testCannot_MoveExceedsBalance() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert();
    dNft.move(id1, id2, 6000e18);
  }
  function testCannot_MoveToInvalidNft() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.InvalidNft.selector));
    dNft.move(id, 1000, 200);
  }

  // -------------------- withdraw --------------------
  function test_Withdraw() public {
    uint id = dNft.mint{value: 50 ether}(address(this));
    assertEq(dNft.id2shares(id), 50000e18);
    assertEq(dyad.totalSupply(), 0);

    vm.warp(block.timestamp + dNft.TIMEOUT());
    dNft.withdraw(id, address(1), 1000e18);

    assertEq(dNft.id2shares(id), 49000e18);
    assertEq(dyad.balanceOf(address(1)), 1000e18);
    assertEq(dyad.totalSupply(), 1000e18);

    dNft.withdraw(id, address(1), 1000e18);
    assertEq(dNft.id2shares(id), 48000e18);
    assertEq(dyad.balanceOf(address(1)), 2000e18);
    assertEq(dyad.totalSupply(), 2000e18);
  }
  function testCannot_WithdrawIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));
    dNft.withdraw(id, address(1), 1000e18);
  }
  function testCannot_WithdrawCrTooLow() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.warp(block.timestamp + dNft.TIMEOUT());
    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooLow.selector));
    dNft.withdraw(id, address(1), 2000e18);
  }
  function testCannot_WithdrawExceedsDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert();
    dNft.withdraw(id, address(1), 6000e18);
  }

  // -------------------- redeemDyad --------------------
  function test_RedeemDyad() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.warp(block.timestamp + dNft.TIMEOUT());
    dNft.withdraw(id, address(this), 1000e18);
    assertEq(dyad.balanceOf(address(this)), 1000e18);
    dNft.redeemDyad(id, address(1), 1000e18);
    assertEq(dyad.balanceOf(address(this)), 0);
    assertEq(address(1).balance, 1e18);
  }
  // function testCannot_RedeemDyadExceedsBalance() public {
  //   uint id = dNft.mint{value: 5 ether}(address(this));
  //   dNft.withdraw(id, address(this), 1000e18);
  //   assertEq(dyad.balanceOf(address(this)), 1000e18);

  //   vm.expectRevert();
  //   dNft.redeemDyad(address(this), 2000e18);
  // }

  // -------------------- redeemDeposit --------------------
  function test_RedeemDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    assertEq(dNft.id2shares(id), 5000e18);
    assertEq(address(1).balance, 0 ether);

    vm.warp(block.timestamp + dNft.TIMEOUT());
    vm.prank(address(1));
    dNft.redeemDeposit(id, address(1), 1000e18);

    assertEq(dNft.id2shares(id), 4000e18);
    assertEq(address(1).balance, 1 ether);
  }
  // function testFuzz_RedeemDeposit(uint eth) public {
  //   vm.assume(eth > 5 ether);
  //   vm.assume(eth <= address(msg.sender).balance);

  //   uint id = dNft.mint{value: eth}(address(1));
  //   assertEq(address(1).balance, 0 ether);

  //   vm.prank(address(1));
  //   dNft.redeemDeposit(id, address(1), eth*1000);

  //   assertEq(dNft.id2shares(id), 0);
  //   assertEq(address(1).balance, eth);
  // }
  function testCannot_RedeemExceedsDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert();
    dNft.redeemDeposit(id, address(this), 6000e18);
  }
  function testCannot_RedeemDepositIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingPermission.selector));
    dNft.redeemDeposit(id, address(this), 1000e18);
  }

  // -------------------- liquidate --------------------
  function test_Liquidate() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.warp(block.timestamp + dNft.TIMEOUT()); // to avoid the timeout
    dNft.withdraw(id, address(this), 1200e18);
    oracleMock.setPrice(950e8);
    dNft.liquidate{value: 500000 ether}(id, address(1));
    assertEq(dNft.ownerOf(id), address(1));
  }
  function testCannot_Liquidate_CrTooHigh() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooHigh.selector));
    dNft.liquidate(id, address(1));
  }
  function testCannot_Liquidate_CrTooLow() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.warp(block.timestamp + dNft.TIMEOUT()); // to avoid the timeout
    dNft.withdraw(id, address(this), 1200e18);
    oracleMock.setPrice(950e8);
    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooLow.selector));
    dNft.liquidate{value: 100}(id, address(1));
  }
  function testCannot_LiquidateNonExistentId() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    dNft.depositEth{value: 100000 ether}(id1);

    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooHigh.selector));
    dNft.liquidate{value: 500000 ether}(3, address(1));
  }

  // -------------------- grant --------------------
  function test_GrantPermission() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.grant(id, address(1));
    (bool hasPermission, ) = dNft.id2permission(id, address(1));
    assertTrue(hasPermission);
  }
  function testCannot_GrantIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotOwner.selector));
    dNft.grant(id, address(1));
  }

  // -------------------- revoke --------------------
  function test_RevokePermission() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.grant(id, address(1));
    (bool hasPermission, ) = dNft.id2permission(id, address(1));
    assertTrue(hasPermission);
    dNft.revoke(id, address(1));
    (hasPermission, ) = dNft.id2permission(id, address(1));
    assertFalse(hasPermission);
  }
  function testCannot_RevokeIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotOwner.selector));
    dNft.revoke(id, address(1));
  }
}

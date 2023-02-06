// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {IPermissionManager as IP} from "../src/interfaces/IPermissionManager.sol";

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
  // -------------------- deposit --------------------
  function test_Deposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.id2Shares(id), 5000e18);

    dNft.deposit{value: 5 ether}(id);
    assertEq(dNft.id2Shares(id), 10000e18);
  }
  function testCannot_DepositIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IP.MissingPermission.selector));
    dNft.deposit{value: 5 ether}(id);
  }

  // -------------------- move --------------------
  function test_Move() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    assertEq(dNft.id2Shares(id1), 5000e18);
    assertEq(dNft.id2Shares(id2), 5000e18);

    dNft.move(id1, id2, 1000e18);

    assertEq(dNft.id2Shares(id1), 4000e18);
    assertEq(dNft.id2Shares(id2), 6000e18);
  }
  function testCannot_MoveIsNotOwner() public {
    uint id1 = dNft.mint{value: 5 ether}(address(1));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert(abi.encodeWithSelector(IP.MissingPermission.selector));
    dNft.move(id1, id2, 1000e18);
  }
  function testCannot_MoveExceedsBalance() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert();
    dNft.move(id1, id2, 6000e18);
  }

  // -------------------- rebase --------------------
  function test_Rebase() public {
    dNft.mint{value: 6 ether}(address(this));
    uint id2 = dNft.mint{value: 6 ether}(address(this));

    oracleMock.setPrice(1100e8);
    dNft.rebase();

    dNft.withdraw(id2, address(1), 1000e18);
  }

  // -------------------- withdraw --------------------
  function test_Withdraw() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    assertEq(dNft.id2Shares(id), 5000e18);
    assertEq(dyad.totalSupply(), 0);

    dNft.withdraw(id, address(1), 1000e18);

    assertEq(dNft.id2Shares(id), 4000e18);
    assertEq(dyad.balanceOf(address(1)), 1000e18);
    assertEq(dyad.totalSupply(), 1000e18);
  }
  function testCannot_WithdrawIsLocked() public {
    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(this));

    vm.expectRevert(abi.encodeWithSelector(IDNft.Locked.selector));
    dNft.withdraw(id, address(1), 1000e18);
  }
  function testCannot_WithdrawIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IP.MissingPermission.selector));
    dNft.withdraw(id, address(1), 1000e18);
  }
  function testCannot_WithdrawCrTooLow() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert(abi.encodeWithSelector(IDNft.CrTooLow.selector));
    dNft.withdraw(id, address(1), 5000e18);
  }

  // -------------------- redeemDyad --------------------
  function test_RedeemDyad() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 1000e18);
    assertEq(dyad.balanceOf(address(this)), 1000e18);

    dNft.redeemDyad(address(1), 1000e18);

    assertEq(dyad.balanceOf(address(this)), 0);
    assertEq(address(1).balance, 1e18);
  }
  function testCannot_RedeemDyadExceedsBalance() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.withdraw(id, address(this), 1000e18);
    assertEq(dyad.balanceOf(address(this)), 1000e18);

    vm.expectRevert();
    dNft.redeemDyad(address(this), 2000e18);
  }

  // -------------------- redeemDeposit --------------------
  function test_RedeemDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    assertEq(dNft.id2Shares(id), 5000e18);
    assertEq(address(1).balance, 0 ether);

    vm.prank(address(1));
    dNft.redeemDeposit(id, address(1), 1000e18);

    assertEq(dNft.id2Shares(id), 4000e18);
    assertEq(address(1).balance, 1 ether);
  }
  function testCannot_RedeemDepositIsLocked() public {
    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(this));

    vm.expectRevert(abi.encodeWithSelector(IDNft.Locked.selector));
    dNft.redeemDeposit(id, address(this), 1000e18);
  }
  function testCannot_RedeemExceedsDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert();
    dNft.redeemDeposit(id, address(this), 6000e18);
  }
  function testCannot_RedeemDepositIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    vm.expectRevert(abi.encodeWithSelector(IP.MissingPermission.selector));
    dNft.redeemDeposit(id, address(this), 1000e18);
  }

  // -------------------- liquidate --------------------
  function test_Liquidate() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    dNft.deposit{value: 100000 ether}(id1);

    dNft.liquidate{value: 500000 ether}(id2, address(1));

    assertEq(dNft.ownerOf(id2), address(1));
  }
  function testCannot_LiquidateUnderLiquidationThershold() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    vm.expectRevert(abi.encodeWithSelector(IDNft.NotLiquidatable.selector));
    dNft.liquidate{value: 500000 ether}(id, address(1));
  }
  function testCannot_LiquidateMissingShares() public {
    uint id1 = dNft.mint{value: 5 ether}(address(this));
    uint id2 = dNft.mint{value: 5 ether}(address(this));

    dNft.deposit{value: 100000 ether}(id1);

    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingShares.selector));
    dNft.liquidate(id2, address(1));
  }

  // -------------------- grant --------------------
  function test_Grant() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    IP.Permission[] memory pp = new IP.Permission[](2);
    pp[0] = IP.Permission.DEPOSIT;
    pp[1] = IP.Permission.MOVE;

    IP.PermissionSet[] memory ps = new IP.PermissionSet[](1);
    ps[0] = IP.PermissionSet({ operator: address(1), permissions: pp });

    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.DEPOSIT));
    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.MOVE));
    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.WITHDRAW));

    dNft.grant(id, ps);

    assertTrue(dNft.hasPermission(id, address(1), IP.Permission.DEPOSIT));
    assertTrue(dNft.hasPermission(id, address(1), IP.Permission.MOVE));
    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.WITHDRAW));
  }
}

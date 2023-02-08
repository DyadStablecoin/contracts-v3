// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {IPermissionManager as IP} from "../src/interfaces/IPermissionManager.sol";
import {SharesMath} from "../src/libraries/SharesMath.sol";

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
  function testFuzz_MintNft(uint eth) public {
    vm.assume(eth > 5 ether);
    vm.assume(eth <= address(msg.sender).balance);

    uint id = dNft.mint{value: eth}(address(this));
    assertEq(dNft.id2Shares(id), eth*1000); // ETH 2 USD = $1000
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
  function testFuzz_Deposit(uint eth) public {
    vm.assume(eth > 0);
    vm.assume(eth <= address(msg.sender).balance);

    uint id = dNft.mint{value: 5 ether}(address(this));
    dNft.deposit{value: eth}(id);
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
  function testFuzz_Move(uint eth) public {
    vm.assume(eth > 5 ether);
    vm.assume(eth <= address(msg.sender).balance/2);

    uint id1 = dNft.mint{value: eth}(address(this));
    uint id2 = dNft.mint{value: eth}(address(this));

    dNft.move(id1, id2, eth*1000);
    assertEq(dNft.id2Shares(id1), 0);
    assertEq(dNft.id2Shares(id2), eth*1000*2);
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
  function test_RebaseUp() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    uint oldTotalDeposit = dNft.totalDeposit();
    assertEq(oldTotalDeposit, 5000e18);
    uint oldDeposit = SharesMath.shares2Deposit(
      dNft.id2Shares(id),
      dNft.totalDeposit(),
      dNft.totalShares()
    );

    oracleMock.setPrice(1100e8); // 10% increase
    dNft.rebase();

    uint newTotalDeposit = dNft.totalDeposit();
    assertEq(newTotalDeposit, 5000e18 + 500e18);
    uint newDeposit = SharesMath.shares2Deposit(
      dNft.id2Shares(id),
      dNft.totalDeposit(),
      dNft.totalShares()
    );
    assertTrue(newDeposit > oldDeposit);
  }
  function test_RebaseDown() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    uint oldDeposit = SharesMath.shares2Deposit(
      dNft.id2Shares(id),
      dNft.totalDeposit(),
      dNft.totalShares()
    );

    oracleMock.setPrice(900e8); // 10% increase
    dNft.rebase();

    uint newDeposit = SharesMath.shares2Deposit(
      dNft.id2Shares(id),
      dNft.totalDeposit(),
      dNft.totalShares()
    );
    assertTrue(newDeposit < oldDeposit);
  }
  function testCannot_RebaseSamePrice() public {
    vm.expectRevert(abi.encodeWithSelector(IDNft.SamePrice.selector));
    dNft.rebase();
  }

  // -------------------- withdraw --------------------
  function test_Withdraw() public {
    uint id = dNft.mint{value: 50 ether}(address(this));
    assertEq(dNft.id2Shares(id), 50000e18);
    assertEq(dyad.totalSupply(), 0);

    dNft.withdraw(id, address(1), 1000e18);

    assertEq(dNft.id2Shares(id), 49000e18);
    assertEq(dyad.balanceOf(address(1)), 1000e18);
    assertEq(dyad.totalSupply(), 1000e18);

    dNft.withdraw(id, address(1), 1000e18);
    assertEq(dNft.id2Shares(id), 48000e18);
    assertEq(dyad.balanceOf(address(1)), 2000e18);
    assertEq(dyad.totalSupply(), 2000e18);
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
  function testCannot_WithdrawExceedsDeposit() public {
    uint id = dNft.mint{value: 5 ether}(address(this));
    vm.expectRevert();
    dNft.withdraw(id, address(1), 6000e18);
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
  function testFuzz_RedeemDeposit(uint eth) public {
    vm.assume(eth > 5 ether);
    vm.assume(eth <= address(msg.sender).balance);

    uint id = dNft.mint{value: eth}(address(1));
    assertEq(address(1).balance, 0 ether);

    vm.prank(address(1));
    dNft.redeemDeposit(id, address(1), eth*1000);

    assertEq(dNft.id2Shares(id), 0);
    assertEq(address(1).balance, eth);
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

    dNft.deposit{value: 10000 ether}(id1);

    vm.expectRevert(abi.encodeWithSelector(IDNft.MissingShares.selector));
    dNft.liquidate{value: 1 ether}(id2, address(1));
  }

  // -------------------- grant --------------------
  function test_GrantAddPermission() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    IP.Permission[] memory pp = new IP.Permission[](1);
    pp[0] = IP.Permission.MOVE;

    IP.OperatorPermission[] memory ps = new IP.OperatorPermission[](1);
    ps[0] = IP.OperatorPermission({ operator: address(1), permissions: pp });

    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.MOVE));
    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.WITHDRAW));

    // can not give permission in the same block as it was minted in
    vm.roll(block.number + 1);
    dNft.grant(id, ps);

    assertTrue(dNft.hasPermission(id, address(1), IP.Permission.MOVE));
    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.WITHDRAW));
  }
  function test_GrantRevokePermission() public {
    uint id = dNft.mint{value: 5 ether}(address(this));

    IP.Permission[] memory pp = new IP.Permission[](1);
    pp[0] = IP.Permission.MOVE;

    IP.OperatorPermission[] memory ps = new IP.OperatorPermission[](1);
    ps[0] = IP.OperatorPermission({ operator: address(1), permissions: pp });

    // can not give permission in the same block as it was minted in
    vm.roll(block.number + 1);
    dNft.grant(id, ps);

    assertTrue(dNft.hasPermission(id, address(1), IP.Permission.MOVE));

    pp = new IP.Permission[](0);
    ps = new IP.OperatorPermission[](1);
    ps[0] = IP.OperatorPermission({ operator: address(1), permissions: pp });

    dNft.grant(id, ps);

    assertFalse(dNft.hasPermission(id, address(1), IP.Permission.MOVE));
  }
  function testCannot_GrantIsNotOwner() public {
    uint id = dNft.mint{value: 5 ether}(address(1));
    IP.Permission[] memory pp = new IP.Permission[](1);
    pp[0] = IP.Permission.MOVE;
    IP.OperatorPermission[] memory ps = new IP.OperatorPermission[](1);
    ps[0] = IP.OperatorPermission({ operator: address(1), permissions: pp });

    vm.expectRevert(abi.encodeWithSelector(IP.NotOwner.selector));
    dNft.grant(id, ps);
  }

  // -------------------- unlock --------------------
  function test_Unlock() public {
    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(this));
    dNft.unlock(id);
  }
  function testCannot_UnlockIsNotOwner() public {
    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(this));

    vm.prank(address(1));
    vm.expectRevert(abi.encodeWithSelector(IP.NotOwner.selector));
    dNft.unlock(id);
  }
  function testCannot_UnlockIsAlreadyUnlocked() public {
    vm.prank(MAINNET_OWNER);
    uint id = dNft._mint(address(this));

    dNft.unlock(id);
    vm.expectRevert(abi.encodeWithSelector(IDNft.NotLocked.selector));
    dNft.unlock(id);
  }
}

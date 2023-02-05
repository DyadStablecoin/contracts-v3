// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import "forge-std/console.sol";
import {BaseTest} from "./BaseTest.sol";
import {Parameters} from "../src/Parameters.sol";
import {IDNft} from "../src/interfaces/IDNft.sol";
import {IPermissionManager} from "../src/interfaces/IPermissionManager.sol";

contract DNftsTest is BaseTest {
  function testInsidersAllocation() public {
    assertEq(dNft.totalSupply(), GOERLI_INSIDERS.length);

    assertEq(dNft.balanceOf(GOERLI_INSIDERS[0]), 1);
    assertEq(dNft.balanceOf(GOERLI_INSIDERS[1]), 1);
    assertEq(dNft.balanceOf(GOERLI_INSIDERS[2]), 1);

    assertEq(dNft.ownerOf(0), GOERLI_INSIDERS[0]);
    assertEq(dNft.ownerOf(1), GOERLI_INSIDERS[1]);
    assertEq(dNft.ownerOf(2), GOERLI_INSIDERS[2]);

    assertTrue(dNft.ethPrice() > 0); // ethPrice is set by oracle
  }

  // -------------------- mint --------------------
  function testMintNft() public {
    uint id1 = dNft.mint{value: 5  ether}(address(this));
    (uint shares, , ) = dNft.id2Nft(id1);
    console.log("shares: %s", shares);

    uint id2 = dNft.mint{value: 5 ether}(address(this));
    ( shares, , ) = dNft.id2Nft(id2);
    console.log("shares: %s", shares);

    uint id3 = dNft.mint{value: 5 ether}(address(this));
    ( shares, , ) = dNft.id2Nft(id3);
    console.log("shares: %s", shares);

    uint id4 = dNft.mint{value: 5  ether}(address(this));
    ( shares, , ) = dNft.id2Nft(id4);
    console.log("shares: %s", shares);

    uint id5 = dNft.mint{value: 5  ether}(address(this));
    ( shares, , ) = dNft.id2Nft(id5);
    console.log("shares: %s", shares);
  }
//   function testCannotMintToZeroAddress() public {
//     vm.expectRevert("ERC721: mint to the zero address");
//     dNft.mint{value: 5 ether}(address(0));
//   }
//   function testCannotMintNotReachedMinAmount() public {
//     vm.expectRevert(abi.encodeWithSelector(IDNft.DepositTooLow.selector));
//     dNft.mint{value: 1 ether}(address(this));
//   }
//   function testCannotMintExceedsMaxSupply() public {
//     uint nftsLeft = dNft.MAX_SUPPLY() - dNft.totalSupply();
//     for (uint i = 0; i < nftsLeft; i++) {
//       dNft.mint{value: 5 ether}(address(this));
//     }
//     assertEq(dNft.totalSupply(), dNft.MAX_SUPPLY());
//     vm.expectRevert(abi.encodeWithSelector(IDNft.MaxSupply.selector));
//     dNft.mint{value: 5 ether}(address(this));
//   }
}

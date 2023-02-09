// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Owned} from "@solmate/src/auth/Owned.sol";
import {DNft} from "../core/DNft.sol";
import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";

contract Rebaser is Owned {
  DNft          public dNft;
  uint          public id;
  IAggregatorV3 public oracle;

  constructor(DNft _dnft, address _oracle) Owned(msg.sender) {
    dNft = _dnft;
    oracle = IAggregatorV3(_oracle);
  }

  function rebase() external {
    ( , int newPrice, , , ) = oracle.latestRoundData();
    uint oldPrice = dNft.ethPrice();
    bool rebaseUp = uint(newPrice) > oldPrice;
    if (!rebaseUp) {
      dNft.redeemDeposit(id, address(this), dNft.id2Shares(id)/1000);
      dNft.rebase();
      dNft.deposit{value: address(this).balance}(id);
    }
  }

  function setId(uint _id) external onlyOwner {
    id = _id;
  }

  receive () external payable {}
}


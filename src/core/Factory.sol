// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {DNftERC20} from "./DNftERC20.sol";
import {Dyad} from "./Dyad.sol";

contract Factory {
  function deploy(
    address _token, 
    address _oracle,
    string memory _flavor 
  ) public {
    Dyad dyad = new Dyad(
      string.concat("DYAD-", _flavor),
      string.concat("d", _flavor),
      msg.sender
    );
    DNftERC20 dNft = new DNftERC20(
      string.concat("DYAD NFT - ", _flavor),
      string.concat("d", _flavor, "NFT"),
      address(dyad),
      _token,
      msg.sender
    );
  }
}

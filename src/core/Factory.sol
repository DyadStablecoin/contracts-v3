// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Collateral} from "./Collateral.sol";
import {Dyad} from "./Dyad.sol";
import {Nft} from "./Nft.sol";

contract Factory {

  event Deployed(address dNft, address dyad);

  // token => oracle => deployed
  mapping(address => mapping(address => bool)) public deployed;

  Nft public nft;

  constructor(address _nft) {
    nft = new Nft(_nft);
  }

  function deploy(
    address _token, 
    address _oracle,
    string memory _flavor 
  ) public {
    require(!deployed[_token][_oracle]);

    Dyad dyad = new Dyad(
      string.concat("DYAD-", _flavor),
      string.concat("d", _flavor),
      msg.sender
    );
    Collateral collateral = new Collateral(
      address(dyad),
      _token,
      msg.sender
    );

    nft.setLiquidator(address(collateral)); 
    dyad.transferOwnership(address(collateral));
    deployed[_token][_oracle] = true;
    emit Deployed(address(collateral), address(dyad));
  }
}

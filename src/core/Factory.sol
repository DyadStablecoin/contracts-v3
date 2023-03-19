// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {Vault} from "./Vault.sol";
import {Dyad} from "./Dyad.sol";
import {Nft} from "./Nft.sol";

contract Factory {

  event Deployed(address dNft, address dyad);

  // token => oracle => deployed
  mapping(address => mapping(address => bool)) public deployed;

  Nft public nft;

  constructor(address _nft) { nft = Nft(_nft); }

  function deploy(
    address _collateral, 
    address _oracle,
    string memory _flavor 
  ) public {
    require(!deployed[_collateral][_oracle]);

    Dyad dyad = new Dyad(
      string.concat("DYAD-", _flavor),
      string.concat("d", _flavor),
      msg.sender
    );
    Vault vault = new Vault(
      address(nft), 
      address(dyad),
      _collateral,
      msg.sender
    );

    nft.setLiquidator(address(vault)); 
    dyad.transferOwnership(address(vault));
    deployed[_collateral][_oracle] = true;
    emit Deployed(address(vault), address(dyad));
  }
}

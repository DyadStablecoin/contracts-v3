// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {IDNft} from "../interfaces/IDNft.sol";
import {Dyad} from "./Dyad.sol";
import {PermissionManager} from "./PermissionManager.sol";

contract DNft is IDNft, ERC721Enumerable, PermissionManager {
  uint public immutable MAX_SUPPLY;            // Max supply of DNfts
  uint public immutable MIN_MINT_DYAD_DEPOSIT; // Min DYAD deposit to mint a DNft

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  constructor(
      address _dyad,
      address _oracle, 
      uint    _maxSupply,
      uint    _minMintDyadDeposit, 
      address[] memory _insiders
  ) ERC721("Dyad NFT", "dNFT") {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
      MAX_SUPPLY            = _maxSupply;
      MIN_MINT_DYAD_DEPOSIT = _minMintDyadDeposit;

      for (uint i = 0; i < _insiders.length; i++) {
        _mintNft(_insiders[i]); // insiders do not require a DYAD deposit
      }
  }

  // Mint new DNft to `to`
  function _mintNft(address to)
    private 
    returns (uint) {
      uint id = totalSupply();
      if (id >= MAX_SUPPLY) { revert MaxSupply(); }
      _mint(to, id); // will revert if `to` == address(0)
      emit Minted(to, id);
      return id;
  }
}

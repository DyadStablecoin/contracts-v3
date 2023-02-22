// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

import {IAggregatorV3} from "../interfaces/AggregatorV3Interface.sol";
import {Dyad} from "./Dyad.sol";

contract DNft2 is ERC721Enumerable, Owned {
  uint public constant  INSIDER_MINTS             = 300; 
  uint public constant  PUBLIC_MINTS              = 1700; 
  uint public constant  MIN_COLLATERIZATION_RATIO = 3e18; // 300%

  Dyad          public dyad;
  IAggregatorV3 public oracle;

  constructor(
      address _dyad,
      address _oracle, 
      address _owner
  ) ERC721("Dyad NFT", "dNFT") 
    Owned(_owner) {
      dyad                  = Dyad(_dyad);
      oracle                = IAggregatorV3(_oracle);
  }
}

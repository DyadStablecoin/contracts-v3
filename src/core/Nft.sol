// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

contract Nft is ERC721Enumerable, Owned {
  using SafeTransferLib for address;

  event MintNft(uint indexed id, address indexed to);

  error PublicMintsExceeded  ();
  error InsiderMintsExceeded ();
  error IncorrectEthSacrifice();

  uint public constant INSIDER_MINTS = 300; 
  uint public constant PUBLIC_MINTS  = 1700; 
  uint public constant ETH_SACRIFICE = 0.1 ether; 

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  constructor(
      address _owner
  ) ERC721("Dyad NFT", "dNFT") 
    Owned(_owner) {}

  function mintNft(address to)
    external 
    payable
    returns (uint) {
      if (++publicMints > PUBLIC_MINTS) revert PublicMintsExceeded();
      if (msg.value != ETH_SACRIFICE)   revert IncorrectEthSacrifice();
      address(0).safeTransferETH(msg.value); // burn ETH
      return _mintNft(to);
  }

  function mintInsiderNft(address to)
    external 
      onlyOwner
    returns (uint) {
      if (++insiderMints > INSIDER_MINTS) revert InsiderMintsExceeded();
      return _mintNft(to); 
  }

  function _mintNft(address to)
    private 
    returns (uint) {
      uint id = totalSupply();
      _safeMint(to, id); // re-entrancy
      emit MintNft(id, to);
      return id;
  }
}

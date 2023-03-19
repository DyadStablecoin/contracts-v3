// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

import {ERC721, ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import {SafeTransferLib} from "@solmate/src/utils/SafeTransferLib.sol";
import {Owned} from "@solmate/src/auth/Owned.sol";

contract Nft is ERC721Enumerable, Owned {
  using SafeTransferLib for address;

  event MintNft(uint indexed id, address indexed to);
  event Grant  (uint indexed id, address indexed operator);
  event Revoke (uint indexed id, address indexed operator);

  error NotOwner             ();
  error PublicMintsExceeded  ();
  error InsiderMintsExceeded ();
  error IncorrectEthSacrifice();
  error NotLiquidator        ();

  uint public constant INSIDER_MINTS = 300; 
  uint public constant PUBLIC_MINTS  = 1700; 
  uint public constant ETH_SACRIFICE = 0.1 ether; 

  uint public insiderMints; // Number of insider mints
  uint public publicMints;  // Number of public mints

  struct Permission {
    bool    hasPermission; 
    uint248 lastUpdated;
  }

  mapping(address => bool)                         public isLiquidator;
  mapping(uint => mapping (address => Permission)) public id2permission; 
  mapping(uint => uint)                            public id2lastOwnershipChange; 

  modifier isNftOwner(uint id) {
    if (ownerOf(id) != msg.sender) revert NotOwner(); _;
  }

  constructor() ERC721("Dyad NFT", "dNFT") 
                Owned(msg.sender) {}

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

  function grant(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      id2permission[id][operator] = Permission(true, uint248(block.number));
      emit Grant(id, operator);
  }

  function revoke(uint id, address operator) 
    external 
      isNftOwner(id) 
    {
      delete id2permission[id][operator];
      emit Revoke(id, operator);
  }

  function hasPermission(uint id, address operator) 
    public 
    view 
    returns (bool) {
      return (
        ownerOf(id) == operator || 
        (
          id2permission[id][operator].hasPermission && 
          id2permission[id][operator].lastUpdated > id2lastOwnershipChange[id]
        )
      );
  }

  function setLiquidator(address liquidator)
    external 
      onlyOwner 
    {
      isLiquidator[liquidator] = true;
  }

  function liquidate(
      uint id, 
      address to 
  ) public {
      if (!isLiquidator[msg.sender]) revert NotLiquidator();
      _transfer(ownerOf(id), to, id);
  }

  // We have to set `lastOwnershipChange` in order to reset permissions
  function _beforeTokenTransfer(
      address from,
      address to,
      uint id, 
      uint batchSize 
  ) internal 
    override {
      super._beforeTokenTransfer(from, to, id, batchSize);
      id2lastOwnershipChange[id] = block.number; // resets permissions
  }
}

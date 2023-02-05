// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  event AddedShares(uint indexed id, uint amount);
  event Minted     (address indexed to, uint indexed id);
  event Redeemed   (uint indexed from, uint dyad, address indexed to, uint eth);
  event Moved      (uint indexed from, uint indexed to, uint amount);
  event Liquidated (address indexed to, uint indexed id);

  error MaxSupply      ();
  error DepositTooLow  ();
  error NotLiquidatable();
  error MissingShares  ();

  /**
   * @notice Mint a new dNFT
   * @dev Will revert:
   *      - If `msg.value` is not enough to cover the deposit minimum
   *      - If the max supply of dNFTs has been reached
   *      - If `to` is the zero address
   * @dev Emits:
   *      - Minted
   *      - DyadMinted
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function mint(address to) external payable returns (uint id);
}

// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  event Unlocked  (uint indexed id);
  event Added     (uint indexed id, uint amount);
  event Removed   (uint indexed id, uint amount);
  event Minted    (address indexed to, uint indexed id);
  event Liquidated(address indexed from, address indexed to, uint indexed id);
  event Redeemed  (address indexed from, uint amount, address indexed to, uint eth);
  event Moved     (uint indexed from, uint indexed to, uint amount);
  event Withdrawn (uint indexed from, address indexed to, uint amount);
  event Rebased   (uint supplyDelta);

  error SamePrice           ();
  error DepositTooLow       ();
  error NotLiquidatable     ();
  error MissingShares       ();
  error MissingPermission   ();
  error NotOwner            ();
  error CrTooLow            ();
  error Locked              ();
  error NotLocked           ();
  error ZeroShares          ();
  error PublicMintsExceeded ();
  error InsiderMintsExceeded();

  /**
   * @notice Mint a new dNFT to `to`
   * @dev Will revert:
   *      - If the maximum number of public mints has been reached
   *      - If `msg.value` is not enough to cover the deposit minimum
   *      - If `to` is the zero address
   * @dev Emits:
   *      - Minted(address indexed to, uint indexed id)
   *      - AddedShares(uint indexed id, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `msg.value` is zero 
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function mint(address to) external payable returns (uint id);

  /**
   * @notice Mint new insider DNft to `to` 
   * @dev Note:
   *      - An insider dNFT does not require a deposit
   *      - An insider dNFT is locked from the start and can only be unlocked 
   *        by the dNFT owner
   * @dev Will revert:
   *      - If not called by contract owner
   *      - If the maximum number of insider mints has been reached
   *      - If `to` is the zero address
   * @dev Emits:
   *      - Minted(address indexed to, uint indexed id)
   *      - AddedShares(uint indexed id, uint amount)
   * @dev For Auditors:
   *      - I'm aware that I'm misusing the underscore convention to denote a 
   *        private/internal function. I'm doing it to show that this can  
   *        not be called by anyone except for the contract owner.
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function _mint(address to) external returns (uint id);

  /**
   * @notice Deposit ETH for deposited DYAD
   * @dev Will revert:
   *      - If new deposit equals zero shares
   *      - If `totalDeposit` equals 0
   * @dev Emits:
   *      - AddedShares(uint indexed id, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `msg.value` is zero 
   * @param id Id of the dNFT that gets the deposited DYAD
   * @return amount Amount of DYAD deposited
   */
  function deposit(uint id) external payable returns (uint);

  /**
   * @notice Move `shares` `from` one dNFT `to` another dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the `from` dNFT AND does not have the
   *        `MOVE` permission for the `from` dNFT
   *      - `shares` to move exceeds the `from` dNFT shares balance
   * @dev Emits:
   *      - Moved(uint indexed from, uint indexed to, uint shares)
   * @dev For Auditors:
   *      - To save gas it does not check if `shares` is zero 
   *      - To save gas it does not check if `from` == `to`, which is not a 
   *        problem because `move` is symmetrical.
   * @param from Id of the dNFT to move the deposit from
   * @param to Id of the dNFT to move the deposit to
   * @param shares Amount of deposited DYAD shares to move
   */
  function move(uint from, uint to, uint shares) external;

  /**
   * @notice Rebase DYAD total supply to reflect the latest price changes
   * @dev Will revert:
   *      - If the new ETH price has not changed from the last rebase ETH price
   * @dev Emits:
   *      - Rebased(uint supplyDelta)
   * @dev For Auditors:
   *      - The chainlink update threshold is currently set to 50 bps
   * @return supplyDelta Amount of added/removed supply of deposited DYAD
   */
  function rebase() external returns (uint);

  /**
   * @notice Withdraw `amount` of deposited DYAD as an ERC-20 token from dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `WITHDRAW` permission
   *      - If `amount` to withdraw is larger than the dNFT deposit
   *      - If deposit to withdraw equals zero shares
   *      - If Collateralization Ratio is is less than the min collaterization 
   *        ratio after the withdrawal
   * @dev Emits:
   *      - Withdrawn(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - To save gas it only fails implicitly if `from` does not have enough
   *        deposited DYAD, by an underflow in `_subDeposit`
   *      - `collatVault` and `newCollatRatio` are only used once and are therfore
   *        unneccessary declarations that I only use to make the code easier 
   *        to read. Hopefully the optimizer will inline them.
   * @param from Id of the dNFT to withdraw from
   * @param to Address to send the DYAD to
   * @param amount Amount of DYAD to withdraw
   */
  function withdraw(uint from, address to, uint amount) external;

  /**
   * @notice Redeem DYAD ERC20 for ETH
   * @dev Will revert:
   *      - If DYAD to redeem is larger thatn `msg.sender` DYAD balance
   *      - If the ETH transfer fails
   * @dev Emits:
   *      - RedeemedDyad(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - `dyad.burn` is called in the beginning so we can revert as fast as
   *        possible if `msg.sender` does not have enough DYAD. The dyad contract
   *        is trusted so it introduces no re-entrancy risk. The revert is implicit
   *        and happens in the _burn function of the ERC20 contract as an underflow.
   *      - There is a re-entrancy risk while transfering the ETH, that is why the 
   *        `all state changes are done before the ETH transfer. I do not see why
   *        a `nonReentrant` modifier would be needed here, lets save the gas.
   * @param to Address to send the ETH to
   * @param amount Amount of DYAD to redeem
   * @return eth Amount of ETH redeemed for DYAD
   */
  function redeemDyad(address to, uint amount) external returns (uint);

  /**
   * @notice Redeem `amount` of deposited DYAD for ETH
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `REDEEM` permission
   *      - If dNFT is locked
   *      - If deposit to withdraw equals zero shares
   *      - If deposited DYAD to redeem is larger than the dNFT deposit
   *      - If the ETH transfer fails
   * @dev Emits:
   *      - RedeemedDeposit(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - To save gas it only fails implicitly if `from` does not have enough
   *        deposited DYAD, by an underflow in `_subDeposit`
   *      - There is a re-entrancy risk while transfering the ETH, that is why the 
   *        `all state changes are done before the ETH transfer. I do not see why
   *        a `nonReentrant` modifier would be needed here, lets save the gas.
   * @param from Id of the dNFT to redeem from
   * @param to Address to send the ETH to
   * @param amount Amount of DYAD to redeem
   * @return eth Amount of ETH redeemed for DYAD
   */
  function redeemDeposit(uint from, address to, uint amount) external returns (uint);

  /**
   * @notice Liquidate dNFT by covering its missing shares and transfering it 
   *         to a new owner
   * @dev Will revert:
   *      - If dNFT shares are not under the `LIQUIDATION_THRESHLD`
   *      - If new deposit equals zero shares
   *      - If ETH sent is not enough to cover the missing shares
   * @dev Emits:
   *      - Liquidated(address indexed to, uint indexed id)
   * @dev For Auditors:
   *      - No need to check if the dNFT exists because a dNFT `transfer` will
   *        revert if it does not exist.
   *      - We could save gas by not defining `newShares`, but this would make 
   *        the code less readable. Hopefully the optimizer takes care of this.
   *      - All permissions for this dNFT are reset because `_transfer` calls 
   *        `_beforeTokenTransfer`, where we set `lastOwnershipChange`
   * @param id Id of the dNFT to liquidate
   * @param to Address to send the dNFT to
   */
  function liquidate(uint id, address to) external payable;

  /**
   * @notice Grant and/or revoke permissions
   * @notice Minting a DNft and grant it some permissions in the same block is
   *         not possible, because it could be exploited by regular transfers.
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT  
   * @dev Emits:
   *      - Modified(uint indexed id, OperatorPermission[] operatorPermissions)
   * @dev To remove all permissions for a specific operator pass in an empty
   *      `Permission` array for that `OperatorPermission`
   * @param id Id of the dNFT's permissions to modify
   * @param operator Operator to grant/revoke permissions for
   * @param hasPermission Has permission or not
   */
  function grant(uint id, address operator, bool hasPermission) external;

  /**
   * @notice Unlock insider dNFT
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT 
   *      - dNFT is not locked
   * @dev Emits:
   *      - Unlocked(uint indexed id)
   * @param id Id of the dNFT to unlock
   */
  function unlock(uint id) external;
}

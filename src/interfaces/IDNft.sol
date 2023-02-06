// SPDX-License-Identifier: MIT
pragma solidity = 0.8.17;

interface IDNft {
  event AddedShares    (uint indexed id, uint amount);
  event RemovedShares  (uint indexed id, uint amount);
  event Minted         (address indexed to, uint indexed id);
  event Liquidated     (address indexed to, uint indexed id);
  event RedeemedDyad   (address indexed from, uint dyad, address indexed to, uint eth);
  event RedeemedDeposit(uint indexed from, uint dyad, address indexed to, uint eth);
  event Moved          (uint indexed from, uint indexed to, uint amount);
  event Withdrawn      (uint indexed from, address indexed to, uint amount);
  event Rebased        (uint supplyDelta);

  error InsiderMintsExceeded();
  error PublicMintsExceeded ();
  error DepositedInSameBlock();
  error SamePrice         ();
  error DepositTooLow     ();
  error NotLiquidatable   ();
  error MissingShares     ();
  error InsufficientShares();
  error CrTooLow          ();
  error Locked            ();
  error NotLocked         ();

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
   * @param to The address to mint the dNFT to
   * @return id Id of the new dNFT
   */
  function _mint(address to) external payable returns (uint id);

  /**
   * @notice Deposit ETH for deposited DYAD
   * @dev Will revert:
   *      - If `msg.sender` is not the owner of the dNFT AND does not have the
   *        `DEPOSIT` permission
   *      - dNFT is inactive
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
   * @param shares Amount of DYAD to move
   */
  function move(uint from, uint to, uint shares) external;

  /**
   * @notice Rebase DYAD total supply to reflect the latest price changes
   * @dev Will revert:
   *      - If the new ETH price has not changed
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
   *      - If DYAD was deposited into the dNFT in the same block. Needed to
   *        prevent flash-loan attacks
   *      - If `amount` to withdraw is larger than the dNFT deposit
   *      - If Collateralization Ratio is is less than the min collaterization 
   *        ratio after the withdrawal
   * @dev Emits:
   *      - Withdrawn(uint indexed from, address indexed to, uint amount)
   * @dev For Auditors:
   *      - To save gas it does not check if `amount` is 0 
   *      - To prevent flash-loan attacks, `deposit` and 
   *        `withdraw` can not be called for the same dNFT in the same block
   * @param from Id of the dNFT to withdraw from
   * @param to Address to send the DYAD to
   * @param amount Amount of DYAD to withdraw
   * @return collatRatio New Collateralization Ratio after the withdrawal
   */
  function withdraw(uint from, address to, uint amount) external returns (uint);
}

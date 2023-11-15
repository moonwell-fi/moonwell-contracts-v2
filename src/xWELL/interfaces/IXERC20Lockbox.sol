// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4 <0.9.0;

interface IXERC20Lockbox {
  /**
   * @notice Emitted when tokens are deposited into the lockbox
   */

  event Deposit(address _sender, uint256 _amount);

  /**
   * @notice Emitted when tokens are withdrawn from the lockbox
   */

  event Withdraw(address _sender, uint256 _amount);

  /**
   * @notice Reverts when a user tries to deposit native tokens on a non-native lockbox
   */

  error IXERC20Lockbox_NotNative();

  /**
   * @notice Reverts when a user tries to deposit non-native tokens on a native lockbox
   */

  error IXERC20Lockbox_Native();

  /**
   * @notice Reverts when a user tries to withdraw and the call fails
   */

  error IXERC20Lockbox_WithdrawFailed();

  /**
   * @notice Deposit ERC20 tokens into the lockbox
   *
   * @param _amount The amount of tokens to deposit
   */

  function deposit(uint256 _amount) external;

  /**
   * @notice Deposit ERC20 tokens into the lockbox, and send the XERC20 to a user
   *
   * @param _user The user to send the XERC20 to
   * @param _amount The amount of tokens to deposit
   */

  function depositTo(address _user, uint256 _amount) external;

  /**
   * @notice Deposit the native asset into the lockbox, and send the XERC20 to a user
   *
   * @param _user The user to send the XERC20 to
   */

  function depositNativeTo(address _user) external payable;

  /**
   * @notice Withdraw ERC20 tokens from the lockbox
   *
   * @param _amount The amount of tokens to withdraw
   */

  function withdraw(uint256 _amount) external;

  /**
   * @notice Withdraw ERC20 tokens from the lockbox
   *
   * @param _user The user to withdraw to
   * @param _amount The amount of tokens to withdraw
   */

  function withdrawTo(address _user, uint256 _amount) external;
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.17;

import "./MErc20Delegate.sol";

interface MLike {
  function delegate(address delegatee) external;
}

/**
 * @title Moonwell's MLikeDelegate Contract
 * @notice MTokens which can 'delegate votes' of their underlying ERC-20
 * @author Moonwell
 */
contract MLikeDelegate is MErc20Delegate {
  /**
   * @notice Construct an empty delegate
   */
  constructor() public MErc20Delegate() {}

  /**
   * @notice Admin call to delegate the votes of the Moonwell-like underlying
   * @param mLikeDelegatee The address to delegate votes to
   */
  function _delegateMLikeTo(address mLikeDelegatee) external {
    require(msg.sender == admin, "only the admin may set the Moonwell-like delegate");
    MLike(underlying).delegate(mLikeDelegatee);
  }
}

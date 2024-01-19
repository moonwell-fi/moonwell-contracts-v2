pragma solidity 0.8.19;

library Constants {
    /// @notice Values for votes and governance

    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///
    /// ----------------------- CONSTANTS ----------------------- ///
    /// --------------------------------------------------------- ///
    /// --------------------------------------------------------- ///

    /// @notice value for a yes vote
    uint8 public constant VOTE_VALUE_YES = 0;

    /// @notice value for a no vote
    uint8 public constant VOTE_VALUE_NO = 1;

    /// @notice value for an abstain vote
    uint8 public constant VOTE_VALUE_ABSTAIN = 2;

    /// @notice the minimum amount of time for cross chain vote collection.
    /// This ensures that votes cast on other chains have the ability to
    /// be registered even if Wormhole experiences downtime or delays.
    uint256 public constant MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD = 1 days;

    /// @notice the minimum amount of voting power for the proposal threshold
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1_000_000 * 1e18;

    /// @notice the minimum voting period for a proposal, ensures proposals cannot be passed too quickly
    uint256 public constant MIN_VOTING_PERIOD = 2 days;
}

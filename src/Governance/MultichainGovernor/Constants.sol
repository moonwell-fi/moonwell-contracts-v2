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

    /// TODO review these constants before deployment

    /// @notice the minimum amount of time for cross chain vote collection.
    /// This ensures that votes cast on other chains have the ability to
    /// be registered even if Wormhole experiences downtime or delays.
    uint256 public constant MIN_CROSS_CHAIN_VOTE_COLLECTION_PERIOD = 1 hours;

    /// @notice the maximum amount of time for the cross chain vote collection.
    uint256 public constant MAX_CROSS_CHAIN_VOTE_COLLECTION_PERIOD = 14 days;

    /// @notice the minimum amount of voting power for the proposal threshold
    uint256 public constant MIN_PROPOSAL_THRESHOLD = 1_000_000 * 1e18;

    /// @notice the minimum amount of voting power for the proposal threshold
    uint256 public constant MAX_PROPOSAL_THRESHOLD = 500_000_000 * 1e18;

    /// @notice the minimum voting period for a proposal, ensures proposals cannot be passed too quickly
    uint256 public constant MIN_VOTING_PERIOD = 1 hours;

    /// @notice the maximum voting period for a proposal, ensures proposals cannot have a voting period too long
    uint256 public constant MAX_VOTING_PERIOD = 14 days;

    /// @notice maximum amount of live proposals per user
    /// start storage at 2
    uint256 public constant MAX_USER_PROPOSAL_COUNT = 5;

    /// @notice MAX VOTING DELAY should be 14 days
    uint256 public constant MAX_VOTING_DELAY = 14 days;

    /// @notice maximum quorum value is 2.5b
    uint256 public constant MAX_QUORUM = 2_500_000_000 * 1e18;

    /// @notice minimum gas limit for a proposal transaction,
    /// ensures the governor cannot be bricked by a proposal
    /// @notice if the opcode price increases suddenly without warning
    /// on destination chains, this could brick this governance contract
    /// and require the use of break glass transactions to fix
    uint96 public constant MIN_GAS_LIMIT = 400_000;
}

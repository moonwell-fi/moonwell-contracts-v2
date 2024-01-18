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

    /// @notice the number of average seconds per block
    uint256 public constant MOONBEAM_BLOCK_TIME = 12;
}

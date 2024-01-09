pragma solidity 0.8.19;

interface IMultichainGovernor {
    /// TODO define further

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @dev Returns the number of votes for a given user
    /// queries xWELL only
    function getVotingPower(
        address voter,
        uint256 blockNumber
    ) external view returns (uint256);
}

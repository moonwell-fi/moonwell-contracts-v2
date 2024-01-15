pragma solidity 0.8.19;

/// Upgradeable, constructor disables implementation
interface IMultichainVoteCollection {
    /// TODO define further

    /// returns address on moonbeam to target
    function getTargetAddress() external view returns (address);

    /// @dev allows user to cast vote for a proposal
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// @dev Returns the number of votes for a given user
    function getVotingPower(address voter, uint256 blockNumber) external view returns (uint256);

    /// @dev emits the vote VAA for a given proposal
    function emitVoteVAA(uint256 proposalId) external;

    /// @dev allows MultichainGovernor to create a proposal ID
    function createProposalId(bytes memory VAA) external;
}

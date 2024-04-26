// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IArtemisGovernor {
    /// @notice Possible states that a proposal may be in
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    function votingPeriod() external view returns (uint256);

    function currentQuorum() external view returns (uint256);

    function votingDelay() external view returns (uint256);

    function queue(uint256 proposalId) external;

    function execute(uint256 proposalId) external payable;

    function castVote(uint256 proposalId, uint8 vote) external;

    function proposalCount() external view returns (uint256);

    function quorumVotes() external view returns (uint256);

    function proposalThreshold() external view returns (uint256);

    function state(uint256 proposalId) external view returns (ProposalState);

    function timelock() external view returns (address);
}

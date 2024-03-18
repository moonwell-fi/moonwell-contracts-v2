// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";

/// @notice interface for the Artemis Governor Contract
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

        
    function propose(
        address[] memory targets,
        uint[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint);

    function castVote(uint proposalId, uint8 proposalValue) external;

    function queue(uint proposalId) external;

    function execute(uint proposalId) external;

}

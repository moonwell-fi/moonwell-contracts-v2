// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";

/// @notice interface for the Temporal Governor Contract
interface ITemporalGovernor {
    /// ------------- STATE VARIABLES -------------

    /// @notice reference to the wormhole bridge
    function wormholeBridge() external view returns (IWormhole);

    /// @notice Map of chain id => trusted sender
    function allTrustedSenders(uint16) external view returns (bytes32[] memory);

    /// @notice returns whether or not the guardian can pause.
    /// starts true and then is turned false when the guardian pauses
    /// governance can then reactivate it.
    function guardianPauseAllowed() external view returns (bool);

    /// @notice list of transactions queued and awaiting execution
    function queuedTransactions(bytes32) external view returns (bool, uint248);

    /// @notice returns the amount of time a proposal must wait before being processed.
    function proposalDelay() external view returns (uint256);

    struct ProposalInfo {
        bool executed;
        uint248 queueTime;
    }

    /// ------------- STRUCTS -------------

    /// @notice A trusted sender is a contract that is allowed to emit VAAs
    struct TrustedSender {
        uint16 chainId;
        address addr;
    }

    /// ------------- EVENTS -------------

    /// @notice Emitted when a VAA is decoded
    event QueuedTransaction(
        address intendedRecipient,
        address[] targets,
        uint256[] values,
        bytes[] calldatas
    );

    /// @notice Emitted when a transaction is executed
    event ExecutedTransaction(address target, uint256 value, bytes data);

    /// @notice Emitted when a trusted sender is updated
    event TrustedSenderUpdated(uint16 chainId, address addr, bool added);

    /// @notice Emitted when a trusted guardian is revoked
    event GuardianRevoked(address indexed guardian);

    /// @notice Emitted when guardian is changed through a governance proposal
    event GuardianChanged(address indexed guardian);

    /// @notice emitted when guardian pause is granted
    event GuardianPauseGranted(uint256 indexed timestamp);

    /// @notice emitted when contract is trustlessly unpaused
    event PermissionlessUnpaused(uint256 indexed timestamp);

    // Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    // then to a bytes32 *left* aligns it, so we right shift to get the proper data
    function addressToBytes(address addr) external pure returns (bytes32);

    /// ------------- PERMISSIONLESS APIs -------------

    /// @notice Taken mostly from the best practices docs from wormhole.
    /// We explicitly don't care who is relaying this, as long
    /// as the VAA is only processed once AND, critically, intended for this contract.
    /// @param VAA The signed Verified Action Approval to process
    /// @dev callable only when unpaused
    function queueProposal(bytes memory VAA) external;

    /// @notice permissionless function to execute a queued VAA
    /// @param VAA The signed Verified Action Approval to process
    /// @dev callable only when unpaused
    function executeProposal(bytes memory VAA) external;

    /// @notice unpauses the contract, and blocks the guardian from pausing again until governance reapproves them
    function permissionlessUnpause() external;

    /// ------------- GUARDIAN ONLY APIs -------------

    /// @notice Allow the guardian to pause the contract
    function togglePause() external;

    /// @notice fast track execution of a VAA as a VAA, ignoring any waiting times and pauses
    function fastTrackProposalExecution(bytes memory VAA) external;

    /// ------------- GOVERNOR ONLY APIs -------------

    /// @notice grant the guardians the pause ability
    function grantGuardiansPause() external;

    /// @notice only callable through a governance proposal
    /// @dev Updates the list of trusted senders
    /// @param _trustedSenders The list of trusted senders, allowing multiple
    /// trusted sender per chain id
    function setTrustedSenders(
        TrustedSender[] calldata _trustedSenders
    ) external;

    /// @notice only callable through a governance proposal
    /// @dev Removes trusted senders from the list
    /// @param _trustedSenders The list of trusted senders, allowing multiple
    /// trusted sender per chain id
    function unSetTrustedSenders(
        TrustedSender[] calldata _trustedSenders
    ) external;

    /// ------------- GUARDIAN / GOVERNOR ONLY APIs -------------

    /// @notice callable only via a gov proposal (governance) or by the guardian
    /// this revokes guardian's ability, no more pausing or fast tracking and
    /// unpauses the contract if paused
    function revokeGuardian() external;
}

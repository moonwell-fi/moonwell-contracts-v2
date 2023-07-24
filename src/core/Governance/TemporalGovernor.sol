// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IWormhole} from "@protocol/core/Governance/IWormhole.sol";

import {ITemporalGovernor} from "@protocol/core/Governance/ITemporalGovernor.sol";

/// @notice contract that governs the Base deployment of moonwell leveraging the wormhole bridge
/// as the source of truth. Wormhole will be fed in actions from the moonbeam chain and this contract
/// will execute them on base.
/// There are a few assumptions that are made in this contract:
/// 1. Wormhole is secure and will not send malicious messages or be deactivated.
/// 2. Moonbeam is secure.
/// 3. Governance on Moonbeam cannot be compromised.
/// if 1. is untrue and wormhole is deactivated, then this contract will be unable to upgrade the base instance
/// if 1. is untrue and wormhole sends malicious messages, then this contract will be paused, and the guardian
/// will have to fast track a proposal to hand ownership to a new governor, and wormhole will have to revoke
/// the permissions on the compromised validator set.
/// if 2. is untrue, then this contract will be paused until moonbeam is restored
/// if 3. is untrue, then this contract will be paused until moonbeam governance is restored, if gov control
/// cannot be restored, then this governance will be compromised.
contract TemporalGovernor is ITemporalGovernor, Ownable, Pausable {
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /// ----------- IMMUTABLES -----------

    /// @notice reference to the wormhole bridge
    IWormhole public immutable wormholeBridge;

    /// @notice returns the amount of time a proposal must wait before being processed.
    uint256 public immutable proposalDelay;

    /// @notice returns the amount of time until this contract can be unpaused permissionlessly
    uint256 public immutable permissionlessUnpauseTime;

    /// ----------- SINGLE STORAGE SLOT -----------

    /// @notice last paused time
    uint248 public lastPauseTime;

    /// @notice returns whether or not the guardian can pause.
    /// starts true and then is turned false when the guardian pauses
    /// governance can then reactivate it.
    bool public guardianPauseAllowed = true;

    /// ----------- MAPPINGS -----------

    /// @notice Map of chain id => trusted sender
    mapping(uint16 => EnumerableSet.Bytes32Set) private trustedSenders;

    /// @notice Record of processed messages to prevent replaying
    /// and enforce time limits are respected
    mapping(bytes32 => ProposalInfo) public queuedTransactions;

    constructor(
        address wormholeCore,
        uint256 _proposalDelay,
        uint256 _permissionlessUnpauseTime,
        TrustedSender[] memory _trustedSenders
    ) Ownable() {
        wormholeBridge = IWormhole(wormholeCore);
        proposalDelay = _proposalDelay;
        permissionlessUnpauseTime = _permissionlessUnpauseTime;

        // Using https://book.wormhole.com/reference/contracts.html#testnet chain ids and local contracts
        // Mark 0xf16165f1046f1b3cdb37da25e835b986e696313a as trusted to emit from eth mainnet
        // Establish a list of trusted emitters from eash chain
        for (uint256 i = 0; i < _trustedSenders.length; i++) {
            trustedSenders[_trustedSenders[i].chainId].add(
                addressToBytes(_trustedSenders[i].addr)
            );
        }
    }

    /// ------------- VIEW ONLY API -------------

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        bytes32 addr
    ) public view returns (bool) {
        return trustedSenders[chainId].contains(addr);
    }

    /// @notice returns whether or not the address is in the trusted senders list for a given chain
    /// @param chainId The wormhole chain id to check
    /// @param addr The address to check
    function isTrustedSender(
        uint16 chainId,
        address addr
    ) external view returns (bool) {
        return isTrustedSender(chainId, addressToBytes(addr));
    }

    /// @notice returns the list of trusted senders for a given chain
    /// @param chainId The wormhole chain id to check
    /// @return The list of trusted senders
    function allTrustedSenders(uint16 chainId)
        external
        view
        override
        returns (bytes32[] memory)
    {
        bytes32[] memory trustedSendersList = new bytes32[](
            trustedSenders[chainId].length()
        );

        unchecked {
            for (uint256 i = 0; i < trustedSendersList.length; i++) {
                trustedSendersList[i] = trustedSenders[chainId].at(i);
            }
        }

        return trustedSendersList;
    }

    /// @notice Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    /// then to a bytes32 *left* aligns it, so we right shift to get the proper data
    /// @param addr The address to convert
    /// @return The address as a bytes32
    function addressToBytes(address addr) public pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }

    /// @notice only callable through a governance proposal
    /// @dev Updates the list of trusted senders
    /// @param _trustedSenders The list of trusted senders, allowing one
    /// trusted sender per chain id
    function setTrustedSenders(
        TrustedSender[] calldata _trustedSenders
    ) external {
        require(
            msg.sender == address(this),
            "TemporalGovernor: Only this contract can update trusted senders"
        );

        unchecked {
            for (uint256 i = 0; i < _trustedSenders.length; i++) {
                trustedSenders[_trustedSenders[i].chainId].add(
                    addressToBytes(_trustedSenders[i].addr)
                );

                emit TrustedSenderUpdated(
                    _trustedSenders[i].chainId,
                    _trustedSenders[i].addr,
                    true /// added to list
                );
            }
        }
    }

    /// @notice only callable through a governance proposal
    /// @dev Removes trusted senders from the list
    /// @param _trustedSenders The list of trusted senders, allowing multiple
    /// trusted sender per chain id
    function unSetTrustedSenders(
        TrustedSender[] calldata _trustedSenders
    ) external {
        require(
            msg.sender == address(this),
            "TemporalGovernor: Only this contract can update trusted senders"
        );

        unchecked {
            for (uint256 i = 0; i < _trustedSenders.length; i++) {
                trustedSenders[_trustedSenders[i].chainId].remove(
                    addressToBytes(_trustedSenders[i].addr)
                );

                emit TrustedSenderUpdated(
                    _trustedSenders[i].chainId,
                    _trustedSenders[i].addr,
                    false /// removed from list
                );
            }
        }
    }

    /// @notice grant the guardians the pause ability
    function grantGuardiansPause() external {
        require(
            msg.sender == address(this),
            "TemporalGovernor: Only this contract can update grant guardian pause"
        );

        guardianPauseAllowed = true;
        lastPauseTime = 0;

        emit GuardianPauseGranted(block.timestamp);
    }

    /// ------------- GUARDIAN / GOVERNOR ONLY API -------------

    /// @notice callable only via a gov proposal (governance) or by the guardian
    /// this revokes guardian's ability, no more pausing or fast tracking and
    /// unpauses the contract if paused
    function revokeGuardian() external {
        address oldGuardian = owner();
        require(
            msg.sender == oldGuardian || msg.sender == address(this),
            "TemporalGovernor: cannot revoke guardian"
        );

        _transferOwnership(address(0));
        guardianPauseAllowed = false;
        lastPauseTime = 0;

        if (paused()) {
            _unpause();
        }

        emit GuardianRevoked(oldGuardian);
    }

    /// ------------- PERMISSIONLESS APIs -------------

    /// @notice We explicitly don't care who is relaying this, as long
    /// as the VAA is only processed once AND, critically, intended for this contract.
    /// @param VAA The signed Verified Action Approval to process
    /// @dev callable only when unpaused
    function queueProposal(bytes memory VAA) external whenNotPaused {
        _queueProposal(VAA);
    }

    /// @notice Taken mostly from the best practices docs from wormhole.
    /// We explicitly don't care who is relaying this, as long
    /// as the VAA is only processed once AND, critically, intended for this contract.
    /// @param VAA The signed Verified Action Approval to process
    function executeProposal(bytes memory VAA) public whenNotPaused {
        _executeProposal(VAA, false);
    }

    /// @notice unpauses the contract, and blocks the guardian from pausing again until governance reapproves them
    function permissionlessUnpause() external whenPaused {
        /// lastPauseTime cannot be equal to 0 at this point because
        /// block.timstamp on a real chain will always be gt 0 and
        /// toggle pause will set lastPauseTime to block.timestamp
        /// which means if the contract is paused on a live network,
        /// its lastPauseTime cannot be 0
        require(
            lastPauseTime + permissionlessUnpauseTime <= block.timestamp,
            "TemporalGovernor: not past pause window"
        );

        lastPauseTime = 0;
        _unpause();

        assert(!guardianPauseAllowed); /// this should never revert, statement for SMT solving

        emit PermissionlessUnpaused(block.timestamp);
    }

    /// @notice Allow the guardian to process a VAA when the
    /// Temporal Governor is paused this is only for use during
    /// periods of emergency when the governance on moonbeam is
    /// compromised and we need to stop additional proposals from going through.
    /// @param VAA The signed Verified Action Approval to process
    function fastTrackProposalExecution(bytes memory VAA) external onlyOwner {
        _executeProposal(VAA, true); /// override timestamp checks and execute
    }

    /// @notice Allow the guardian to pause the contract
    /// removes the guardians ability to call pause again until governance reaaproves them
    /// starts the timer for the permissionless unpause
    /// cannot call this function if guardian is revoked
    function togglePause() external onlyOwner {
        if (paused()) {
            _unpause();
        } else {
            require(
                guardianPauseAllowed,
                "TemporalGovernor: guardian pause not allowed"
            );

            guardianPauseAllowed = false;
            lastPauseTime = uint248(block.timestamp);
            _pause();
        }

        /// statement for SMT solver
        assert(!guardianPauseAllowed); /// this should be an unreachable state
    }

    /// ------------- HELPER FUNCTIONS -------------

    /// queue a proposal
    function _queueProposal(bytes memory VAA) private {
        /// Checks

        // This call accepts single VAAs and headless VAAs
        (
            IWormhole.VM memory vm,
            bool valid,
            string memory reason
        ) = wormholeBridge.parseAndVerifyVM(VAA);

        // Ensure VAA parsing verification succeeded.
        require(valid, reason);

        address intendedRecipient;
        address[] memory targets; /// contracts to call
        uint256[] memory values; /// native token amount to send
        bytes[] memory calldatas; /// calldata to send

        (intendedRecipient, targets, values, calldatas) = abi.decode(
            vm.payload,
            (address, address[], uint256[], bytes[])
        );

        _sanityCheckPayload(targets, values, calldatas);

        // Very important to check to make sure that the VAA we're processing is specifically designed
        // to be sent to this contract
        require(intendedRecipient == address(this), "TemporalGovernor: Incorrect destination");

        // Ensure the emitterAddress of this VAA is a trusted address
        require(
            trustedSenders[vm.emitterChainId].contains(vm.emitterAddress), /// allow multiple per chainid
            "TemporalGovernor: Invalid Emitter Address"
        );

        /// Check that the VAA hasn't already been processed (replay protection)
        require(
            queuedTransactions[vm.hash].queueTime == 0,
            "TemporalGovernor: Message already queued"
        );

        /// Effect

        // Add the VAA to queued messages so that it can't be replayed
        queuedTransactions[vm.hash].queueTime = uint248(block.timestamp);

        emit QueuedTransaction(intendedRecipient, targets, values, calldatas);
    }

    function _executeProposal(bytes memory VAA, bool overrideDelay) private {
        // This call accepts single VAAs and headless VAAs
        (
            IWormhole.VM memory vm,
            bool valid,
            string memory reason
        ) = wormholeBridge.parseAndVerifyVM(VAA);

        require(valid, reason); /// ensure VAA parsing verification succeeded

        if (!overrideDelay) {
            require(
                queuedTransactions[vm.hash].queueTime != 0,
                "TemporalGovernor: tx not queued"
            );
            require(
                queuedTransactions[vm.hash].queueTime + proposalDelay <=
                    block.timestamp,
                "TemporalGovernor: timelock not finished"
            );
        } else if (queuedTransactions[vm.hash].queueTime == 0) {
            /// if queue time is 0 due to fast track execution, set it to current block timestamp
            queuedTransactions[vm.hash].queueTime = uint248(block.timestamp);
        }

        // Ensure the emitterAddress of this VAA is a trusted address
        require(
            trustedSenders[vm.emitterChainId].contains(vm.emitterAddress), /// allow multiple per chainid
            "TemporalGovernor: Invalid Emitter Address"
        );

        require(
            !queuedTransactions[vm.hash].executed,
            "TemporalGovernor: tx already executed"
        );

        queuedTransactions[vm.hash].executed = true;

        address[] memory targets; /// contracts to call
        uint256[] memory values; /// native token amount to send
        bytes[] memory calldatas; /// calldata to send
        (, targets, values, calldatas) = abi.decode(
            vm.payload,
            (address, address[], uint256[], bytes[])
        );

        /// Interaction (s)

        _sanityCheckPayload(targets, values, calldatas);

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            uint256 value = values[i];
            bytes memory data = calldatas[i];

            // Go make our call, and if it is not successful revert with the error bubbling up
            (bool success, bytes memory returnData) = target.call{value: value}(
                data
            );

            /// revert on failure with error message if any
            require(success, string(returnData));

            emit ExecutedTransaction(target, value, data);
        }
    }

    /// @notice arity check for payload
    function _sanityCheckPayload(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas
    ) private pure {
        require(targets.length != 0, "TemporalGovernor: Empty proposal");
        require(
            targets.length == values.length &&
                targets.length == calldatas.length,
            "TemporalGovernor: Arity mismatch for payload"
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20Votes} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";
import "@utils/ChainIds.sol";

import {Address} from "@utils/Address.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ProposalChecker} from "@proposals/utils/ProposalChecker.sol";
import {ITemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MarketCreationHook} from "@proposals/hooks/MarketCreationHook.sol";
import {BridgeValidationHook} from "@proposals/hooks/BridgeValidationHook.sol";
import {ProposalAction, ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {IMultichainGovernorV2} from "@protocol/governance/multichain/IMultichainGovernorV2.sol";
import {IVotingPowerAggregator} from "@protocol/governance/multichain/IVotingPowerAggregator.sol";

/// @title HybridProposalV2
/// @notice Proposal type for MultichainGovernorV2 where Ethereum is the governance hub.
/// This proposal type supports actions on Ethereum (local) and cross-chain actions
/// to Moonbeam, Base, and Optimism via TemporalGovernor contracts.
///
/// Key differences from HybridProposal:
/// - Ethereum is the hub chain (not Moonbeam)
/// - Uses MultichainGovernorV2 instead of MultichainGovernor
/// - Cross-chain messages originate from Ethereum's Wormhole Core
/// - Moonbeam, Base, and Optimism receive proposals via their TemporalGovernors
abstract contract HybridProposalV2 is
    Proposal,
    ProposalChecker,
    MarketCreationHook,
    BridgeValidationHook
{
    using Strings for string;
    using Address for address;
    using ChainIds for uint256;
    using ProposalActions for *;

    /// @notice nonce for wormhole, unused by Temporal Governor
    uint32 public nonce = uint32(vm.envOr("NONCE", uint256(0)));

    /// @notice finalized finality https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint8 public constant consistencyLevel = 1;

    /// @notice Verify all proposal actions before execution
    /// @dev Calls both market creation and bridge validation hooks
    /// @param proposal Array of proposal actions to validate
    function _verifyActionsPreRun(ProposalAction[] memory proposal) internal {
        // Validate market creation actions
        _verifyMarketCreationActions(proposal);

        // Validate bridge actions
        _verifyBridgeActions(proposal);
    }

    /// @notice Extract the first 4 bytes (function selector) from calldata
    /// @dev Provides single implementation for both hooks to avoid duplication
    /// @param toSlice The bytes to extract from
    /// @return functionSignature The extracted function selector
    function bytesToBytes4(
        bytes memory toSlice
    )
        public
        pure
        override(MarketCreationHook, BridgeValidationHook)
        returns (bytes4 functionSignature)
    {
        if (toSlice.length < 4) {
            return bytes4(0);
        }

        assembly {
            functionSignature := mload(add(toSlice, 0x20))
        }
    }

    /// @notice actions to run against contracts
    ProposalAction[] public actions;

    /// @notice allows asserting wormhole core correctly emits data to temporal governor
    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    /// @notice push an action to the Hybrid proposal without specifying a
    /// proposal type. infer the proposal type from the current chainid
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param description description of the action
    function _pushAction(
        address target,
        bytes memory data,
        string memory description
    ) internal {
        uint256 fork = vm.activeFork();
        _pushAction(target, 0, data, description, _forkIdToActionType(fork));
    }

    /// @notice maps a fork ID to the corresponding ActionType
    /// @dev explicit mapping avoids reliance on enum ordinal == fork ID
    function _forkIdToActionType(
        uint256 forkId
    ) internal pure returns (ActionType) {
        if (forkId == MOONBEAM_FORK_ID) return ActionType.Moonbeam;
        if (forkId == BASE_FORK_ID) return ActionType.Base;
        if (forkId == OPTIMISM_FORK_ID) return ActionType.Optimism;
        if (forkId == ETHEREUM_FORK_ID) return ActionType.Ethereum;
        revert("HybridProposalV2: invalid fork id");
    }

    /// @notice push an action to the Hybrid proposal
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param proposalType whether this action is on ethereum, moonbeam, base, or optimism
    function _pushAction(
        address target,
        bytes memory data,
        string memory description,
        ActionType proposalType
    ) internal {
        _pushAction(target, 0, data, description, proposalType);
    }

    /// @notice push an action to the Hybrid proposal
    /// @param target the target contract
    /// @param value msg.value to send to target
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param actionType which chain this proposal action belongs to
    function _pushAction(
        address target,
        uint256 value,
        bytes memory data,
        string memory description,
        ActionType actionType
    ) internal {
        actions.push(
            ProposalAction({
                target: target,
                value: value,
                data: data,
                description: description,
                actionType: actionType
            })
        );
    }

    /// @notice push an action to the Hybrid proposal with 0 value and no description
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param proposalType which chain this proposal action belongs to
    function _pushAction(
        address target,
        bytes memory data,
        ActionType proposalType
    ) internal {
        _pushAction(target, 0, data, "", proposalType);
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// ------------------- VIEWS ---------------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    function getProposalActionSteps()
        public
        view
        returns (
            address[] memory,
            uint256[] memory,
            bytes[] memory,
            ActionType[] memory,
            string[] memory
        )
    {
        address[] memory targets = new address[](actions.length);
        uint256[] memory values = new uint256[](actions.length);
        bytes[] memory calldatas = new bytes[](actions.length);
        ActionType[] memory network = new ActionType[](actions.length);
        string[] memory descriptions = new string[](actions.length);

        /// all actions
        for (uint256 i = 0; i < actions.length; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            calldatas[i] = actions[i].data;
            descriptions[i] = actions[i].description;
            network[i] = actions[i].actionType;
        }

        return (targets, values, calldatas, network, descriptions);
    }

    function getTemporalGovCalldata(
        address temporalGovernor,
        ProposalAction[] memory proposalActions
    ) public view returns (bytes memory timelockCalldata) {
        require(
            temporalGovernor != address(0),
            "getTemporalGovCalldata: Invalid temporal governor"
        );

        address[] memory targets = new address[](proposalActions.length);
        uint256[] memory values = new uint256[](proposalActions.length);
        bytes[] memory payloads = new bytes[](proposalActions.length);

        for (uint256 i = 0; i < proposalActions.length; i++) {
            targets[i] = proposalActions[i].target;
            values[i] = proposalActions[i].value;
            payloads[i] = proposalActions[i].data;
        }

        timelockCalldata = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            nonce,
            abi.encode(temporalGovernor, targets, values, payloads),
            consistencyLevel
        );
    }

    /// @notice return arrays of all items in the proposal that the
    /// MultichainGovernorV2 on Ethereum will execute
    /// all items are in the same order as the proposal
    function getTargetsPayloadsValues(
        Addresses addresses
    )
        public
        view
        override
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address temporalGovernorMoonbeam = addresses.isAddressSet(
            "TEMPORAL_GOVERNOR",
            block.chainid.toMoonbeamChainId()
        )
            ? addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                block.chainid.toMoonbeamChainId()
            )
            : address(0);

        address temporalGovernorBase = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            block.chainid.toBaseChainId()
        );

        address temporalGovernorOptimism = addresses.isAddressSet(
            "TEMPORAL_GOVERNOR",
            block.chainid.toOptimismChainId()
        )
            ? addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                block.chainid.toOptimismChainId()
            )
            : address(0);

        return
            getTargetsPayloadsValues(
                addresses.getAddress(
                    "WORMHOLE_CORE",
                    block.chainid.toEthereumChainId()
                ),
                temporalGovernorMoonbeam,
                temporalGovernorBase,
                temporalGovernorOptimism
            );
    }

    /// @notice number of wormhole publishMessage chunks a chain's bundled
    /// actions are split into. Default 1: all of a chain's actions ride in a
    /// single temporal governor payload. Override to split an oversized chain
    /// bundle across multiple governor actions (each chunk becomes its own
    /// publishMessage call / VAA) so the proposal can be submitted in parts
    /// via the governor's init + append propose() batching.
    /// @dev chunkCount and chunkActions describe one partition and MUST be
    /// overridden together: a chunkCount that disagrees with the slices
    /// chunkActions returns silently drops or duplicates actions.
    function chunkCount(ActionType) public view virtual returns (uint256) {
        return 1;
    }

    /// @notice the actions belonging to chunk `index` for `actionType`.
    /// Overrides must partition actions.filter(actionType) in order without
    /// splitting dependent action sequences (e.g. reduce -> approve -> repay)
    /// across chunks, since each chunk executes as an independent temporal
    /// governor proposal on the destination chain.
    /// @dev MUST be overridden together with chunkCount — see chunkCount.
    function chunkActions(
        ActionType actionType,
        uint256 index
    ) public view virtual returns (ProposalAction[] memory) {
        index;
        return actions.filter(actionType);
    }

    /// @notice strictly increasing governor-action indices at which the
    /// proposal is split into successive propose() calls when submitted in
    /// batches. Empty (default): single propose() call with finalize = true.
    /// With n split points the proposal is submitted in n + 1 calls: the
    /// first initializes the proposal with actions [0, splits[0]) and
    /// finalize = false, each subsequent call appends the next segment, and
    /// the last call sets finalize = true. Use together with chunkCount /
    /// chunkActions to keep each call's calldata small enough to submit.
    function batchProposeSplits()
        public
        view
        virtual
        returns (uint256[] memory)
    {
        return new uint256[](0);
    }

    /// @notice returns the total number of actions in the proposal
    /// including moonbeam, base and optimism actions which are each bundled into
    /// chunkCount() actions to wormhole core on Ethereum (default one).
    function allActionTypesCount() public view returns (uint256 count) {
        uint256 moonbeamActions = actions.proposalActionTypeCount(
            ActionType.Moonbeam
        );
        moonbeamActions = moonbeamActions > 0
            ? chunkCount(ActionType.Moonbeam)
            : 0;

        uint256 baseActions = actions.proposalActionTypeCount(ActionType.Base);
        baseActions = baseActions > 0 ? chunkCount(ActionType.Base) : 0;

        uint256 optimismActions = actions.proposalActionTypeCount(
            ActionType.Optimism
        );
        optimismActions = optimismActions > 0
            ? chunkCount(ActionType.Optimism)
            : 0;

        uint256 ethereumActions = actions.proposalActionTypeCount(
            ActionType.Ethereum
        );

        return
            moonbeamActions + baseActions + optimismActions + ethereumActions;
    }

    ///
    /// ------------------------------------------
    ///   Governance Proposal Calldata Structure
    /// ------------------------------------------
    ///
    /// - Ethereum Actions:
    ///  - actions whose target chain are non wormhole Ethereum smart contracts
    ///  this could be protocol actions on the Ethereum chain
    ///
    /// - Moonbeam Actions:
    ///  - actions whose target chain are Moonbeam smart contracts
    ///  sent through wormhole core contracts by calling publish message
    ///
    /// - Base Actions:
    ///  - actions whose target chain are Base smart contracts
    ///  sent through wormhole core contracts by calling publish message
    ///
    /// - Optimism Actions:
    ///  - actions whose target chain are Optimism smart contracts
    ///  sent through wormhole core contracts by calling publish message
    ///

    /// @notice return arrays of all items in the proposal that the
    /// MultichainGovernorV2 on Ethereum will execute
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues(
        address wormholeCore,
        address temporalGovernorMoonbeam,
        address temporalGovernorBase,
        address temporalGovernorOptimism
    ) public view returns (address[] memory, uint256[] memory, bytes[] memory) {
        uint256 proposalLength = allActionTypesCount();

        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        uint256 currIndex = 0;

        // First, add all Ethereum (local) actions
        for (uint256 i = 0; i < actions.length; i++) {
            /// target cannot be address 0 as that call will fail
            require(
                actions[i].target != address(0),
                "Invalid target for governance"
            );

            /// value can be 0
            /// arguments can be 0 as long as eth is sent
            /// if there are no args and no eth, the action is not valid
            require(
                (actions[i].data.length == 0 && actions[i].value > 0) ||
                    actions[i].data.length > 0,
                "Invalid arguments for governance"
            );

            if (actions[i].actionType == ActionType.Ethereum) {
                targets[currIndex] = actions[i].target;
                values[currIndex] = actions[i].value;
                payloads[currIndex] = actions[i].data;

                currIndex++;
            }
        }

        /// only get temporal governor calldata if there are actions to execute on Moonbeam
        if (
            temporalGovernorMoonbeam != address(0) &&
            actions.proposalActionTypeCount(ActionType.Moonbeam) != 0
        ) {
            for (uint256 c = 0; c < chunkCount(ActionType.Moonbeam); c++) {
                targets[currIndex] = wormholeCore;
                values[currIndex] = 0;
                payloads[currIndex] = getTemporalGovCalldata(
                    temporalGovernorMoonbeam,
                    chunkActions(ActionType.Moonbeam, c)
                );
                currIndex++;
            }
        }

        /// only get temporal governor calldata if there are actions to execute on Base
        if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
            for (uint256 c = 0; c < chunkCount(ActionType.Base); c++) {
                targets[currIndex] = wormholeCore;
                values[currIndex] = 0;
                payloads[currIndex] = getTemporalGovCalldata(
                    temporalGovernorBase,
                    chunkActions(ActionType.Base, c)
                );
                currIndex++;
            }
        }

        /// only get temporal governor calldata if there are actions to execute on Optimism
        if (
            temporalGovernorOptimism != address(0) &&
            actions.proposalActionTypeCount(ActionType.Optimism) != 0
        ) {
            for (uint256 c = 0; c < chunkCount(ActionType.Optimism); c++) {
                targets[currIndex] = wormholeCore;
                values[currIndex] = 0;
                payloads[currIndex] = getTemporalGovCalldata(
                    temporalGovernorOptimism,
                    chunkActions(ActionType.Optimism, c)
                );
                currIndex++;
            }
        }

        return (targets, values, payloads);
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// --------------------- Printing ----------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    function printProposalActionSteps() public override {
        console.log(
            "\n\n--------------- Proposal Description ----------------\n",
            string(PROPOSAL_DESCRIPTION)
        );

        console.log(
            "\n\n----------------- Proposal Actions ------------------\n"
        );

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ActionType[] memory network,
            string[] memory descriptions
        ) = getProposalActionSteps();

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("%d). %s", i + 1, descriptions[i]);
            console.log(
                "target: %s\nvalue: %d\npayload:",
                targets[i],
                values[i]
            );
            emit log_bytes(calldatas[i]);
            console.log(
                "Proposal type: %s\n",
                uint256(network[i]).chainForkToName()
            );

            console.log("\n");
        }
    }

    /// @notice Getter function for `MultichainGovernorV2.propose()` calldata
    /// @param addresses the addresses contract
    function getCalldata(
        Addresses addresses
    ) public view virtual returns (bytes memory) {
        require(
            bytes(_proposeDescription()).length > 0,
            "No proposal description"
        );

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues(addresses);

        bytes memory proposalCalldata = abi.encodeWithSignature(
            "propose(address[],uint256[],bytes[],string,bool)",
            targets,
            values,
            payloads,
            _proposeDescription(),
            true // finalize = true
        );

        return proposalCalldata;
    }

    /// @notice calldata for the first of the batched propose() calls:
    /// governor actions [0, batchProposeSplits()[0]), finalize = false.
    /// Only meaningful when batchProposeSplits() is non-empty.
    function getBatchProposeCalldata(
        Addresses addresses
    ) public view returns (bytes memory) {
        uint256[] memory splits = batchProposeSplits();
        require(splits.length > 0, "batch propose submission not enabled");

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues(addresses);

        _validateBatchSplits(splits, targets.length);

        return _encodeBatchPropose(targets, values, payloads, splits[0]);
    }

    /// @notice calldata for append call `appendIndex` (0-based, in
    /// [0, batchProposeSplits().length)): the segment's governor actions
    /// appended to `proposalId`, finalize = true on the last segment.
    /// `proposalId` is the id returned by the first call.
    function getBatchAppendCalldata(
        Addresses addresses,
        uint256 proposalId,
        uint256 appendIndex
    ) public view returns (bytes memory) {
        uint256[] memory splits = batchProposeSplits();
        require(appendIndex < splits.length, "invalid batch append index");

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues(addresses);

        _validateBatchSplits(splits, targets.length);

        return
            _encodeBatchAppend(
                proposalId,
                targets,
                values,
                payloads,
                splits[appendIndex],
                appendIndex + 1 < splits.length
                    ? splits[appendIndex + 1]
                    : targets.length,
                appendIndex + 1 == splits.length // finalize on last segment
            );
    }

    /// @notice submit the proposal to the governor in splits.length + 1
    /// batched propose() calls: init with the first segment (finalize =
    /// false), then append each remaining segment, finalizing on the last
    /// one. Returns the init call's returndata (the abi-encoded proposal id).
    function _submitBatchPropose(
        address payable governorAddress,
        address caller,
        uint256 cost,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256[] memory splits
    ) internal returns (bytes memory data) {
        _validateBatchSplits(splits, targets.length);

        // The id the init call will be assigned (propose does ++proposalCount)
        uint256 batchProposalId = MultichainGovernorV2(governorAddress)
            .proposalCount() + 1;

        // Encode every call up front: init with the first segment
        // (finalize = false), then one append per remaining segment,
        // finalizing on the last
        bytes[] memory calls = new bytes[](splits.length + 1);
        calls[0] = _encodeBatchPropose(targets, values, payloads, splits[0]);

        for (uint256 s = 1; s <= splits.length; s++) {
            uint256 end = s == splits.length ? targets.length : splits[s];
            calls[s] = _encodeBatchAppend(
                batchProposalId,
                targets,
                values,
                payloads,
                splits[s - 1],
                end,
                s == splits.length // finalize on the last segment
            );
        }

        data = _submitGovernorCalls(governorAddress, caller, cost, calls);

        require(
            abi.decode(data, (uint256)) == batchProposalId,
            "batch propose proposal id mismatch"
        );
    }

    /// @notice max gas a SINGLE propose() call may consume in simulation.
    /// Each batched call is its own mainnet transaction, so the binding
    /// constraint is per-call (it must fit an Ethereum block with headroom),
    /// not the sum across calls — a large epoch legitimately spends more
    /// than any single-block budget in total.
    uint256 public constant MAX_PROPOSE_CALL_GAS = 30_000_000;

    /// @notice submit the encoded propose() calls in order. Only the last
    /// call carries value (bridging happens at finalize). Returns the first
    /// call's returndata (the abi-encoded proposal id).
    function _submitGovernorCalls(
        address payable governorAddress,
        address caller,
        uint256 finalValue,
        bytes[] memory calls
    ) internal returns (bytes memory data) {
        for (uint256 i = 0; i < calls.length; i++) {
            uint256 gasBefore = gasleft();

            vm.prank(caller);
            (bool success, bytes memory returndata) = governorAddress.call{
                value: i == calls.length - 1 ? finalValue : 0,
                gas: 52_000_000
            }(calls[i]);

            if (i == 0) {
                data = returndata;
            }

            if (!success) {
                _revertWithReturndata(
                    returndata,
                    "batch propose multichain governor v2 failed"
                );
            }

            require(
                gasBefore - gasleft() <= MAX_PROPOSE_CALL_GAS,
                string.concat(
                    "Proposal propose call ",
                    vm.toString(i),
                    " gas limit exceeded"
                )
            );
        }
    }

    function _validateBatchSplits(
        uint256[] memory splits,
        uint256 actionCount
    ) internal pure {
        for (uint256 i = 0; i < splits.length; i++) {
            require(
                splits[i] > 0 && splits[i] < actionCount,
                "batch split index out of range"
            );
            require(
                i == 0 || splits[i] > splits[i - 1],
                "batch splits not strictly increasing"
            );
        }
    }

    function _encodeBatchPropose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 end
    ) internal view returns (bytes memory) {
        (
            address[] memory t,
            uint256[] memory v,
            bytes[] memory p
        ) = _sliceRange(targets, values, payloads, 0, end);

        return
            abi.encodeWithSignature(
                "propose(address[],uint256[],bytes[],string,bool)",
                t,
                v,
                p,
                _proposeDescription(),
                false // finalize = false, completed by the append calls
            );
    }

    function _encodeBatchAppend(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 start,
        uint256 end,
        bool finalize
    ) internal pure returns (bytes memory) {
        (
            address[] memory t,
            uint256[] memory v,
            bytes[] memory p
        ) = _sliceRange(targets, values, payloads, start, end);

        return
            abi.encodeWithSignature(
                "propose(uint256,address[],uint256[],bytes[],bool)",
                proposalId,
                t,
                v,
                p,
                finalize
            );
    }

    function _sliceRange(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory payloads,
        uint256 start,
        uint256 end
    )
        internal
        pure
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address[] memory t = new address[](end - start);
        uint256[] memory v = new uint256[](end - start);
        bytes[] memory p = new bytes[](end - start);

        for (uint256 i = start; i < end; i++) {
            t[i - start] = targets[i];
            v[i - start] = values[i];
            p[i - start] = payloads[i];
        }

        return (t, v, p);
    }

    function _revertWithReturndata(
        bytes memory returndata,
        string memory fallbackMessage
    ) internal pure {
        if (returndata.length > 0) {
            assembly {
                let returndata_size := mload(returndata)
                revert(add(32, returndata), returndata_size)
            }
        }
        revert(fallbackMessage);
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// -------------------- OVERRIDES ----------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    /// @notice Print out the proposal action steps and which chains they were run on
    function printCalldata(Addresses addresses) public view override {
        console.log(
            "\n\n----------------- Proposal Calldata ------------------\n"
        );
        console.logBytes(getCalldata(addresses));

        uint256[] memory splits = batchProposeSplits();
        if (splits.length != 0) {
            console.log(
                "\n\n------------- Batched Proposal Calldata --------------\n"
            );
            console.log(
                "call 1 of %s - initializes the proposal (finalize = false):",
                splits.length + 1
            );
            console.logBytes(getBatchProposeCalldata(addresses));

            uint256 proposalId = vm.envOr("BATCH_PROPOSAL_ID", uint256(0));
            console.log(
                "\nappend calls below are encoded for proposal id %s. After call 1 is mined, set BATCH_PROPOSAL_ID to the returned id and re-run DO_PRINT to regenerate.",
                proposalId
            );

            for (uint256 s = 0; s < splits.length; s++) {
                console.log(
                    s == splits.length - 1
                        ? "\ncall %s of %s - appends the last segment and finalizes:"
                        : "\ncall %s of %s - appends the next segment (finalize = false):",
                    s + 2,
                    splits.length + 1
                );
                console.logBytes(
                    getBatchAppendCalldata(addresses, proposalId, s)
                );
            }
        }
    }

    function deploy(Addresses, address) public virtual override {}

    function afterDeploy(Addresses, address) public virtual override {}

    function build(Addresses) public virtual override {}

    function teardown(Addresses, address) public virtual override {}

    function simulate(
        Addresses addresses,
        address
    ) public virtual override mockHook(addresses) {
        require(actions.length != 0, "no governance proposal actions to run");

        vm.selectFork(ETHEREUM_FORK_ID);
        addresses.addRestriction(block.chainid.toEthereumChainId());

        _runEthereumMultichainGovernorV2(addresses, address(3));
        addresses.removeRestriction();

        uint256 blockTimestamp = block.timestamp;

        if (actions.proposalActionTypeCount(ActionType.Moonbeam) != 0) {
            vm.selectFork(MOONBEAM_FORK_ID);
            vm.warp(blockTimestamp);
            _runExtChainChunks(addresses, ActionType.Moonbeam);
        }

        if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
            vm.selectFork(BASE_FORK_ID);
            vm.warp(blockTimestamp);
            _runExtChainChunks(addresses, ActionType.Base);
        }

        if (actions.proposalActionTypeCount(ActionType.Optimism) != 0) {
            vm.selectFork(OPTIMISM_FORK_ID);
            vm.warp(blockTimestamp);
            _runExtChainChunks(addresses, ActionType.Optimism);
        }

        blockTimestamp = block.timestamp;

        vm.selectFork(uint256(primaryForkId()));
        vm.warp(blockTimestamp);
    }

    /// @notice Runs the proposal on Ethereum using MultichainGovernorV2
    /// @param addresses the addresses contract
    /// @param caller the proposer address
    function _runEthereumMultichainGovernorV2(
        Addresses addresses,
        address caller
    ) internal {
        _verifyActionsPreRun(actions.filter(ActionType.Ethereum));

        addresses.addRestriction(block.chainid);

        address payable governorAddress = payable(
            addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
        );
        MultichainGovernorV2 governor = MultichainGovernorV2(governorAddress);

        {
            // Get the VotingPowerAggregator to deal voting power
            IVotingPowerAggregator votingPowerAggregator = governor
                .votingPower();
            address xWell = addresses.getAddress("xWELL_PROXY");

            // Ensure proposer meets minimum proposal threshold and quorum votes to pass the proposal
            uint256 quorumVotes = governor.quorum();
            uint256 proposalThreshold = governor.proposalThreshold();
            uint256 votingPower = quorumVotes > proposalThreshold
                ? quorumVotes
                : proposalThreshold;

            // Deal xWELL tokens to caller for voting power
            deal(xWell, caller, votingPower);

            // Delegate votes to self
            vm.prank(caller);
            ERC20Votes(xWell).delegate(caller);
        }

        bytes memory data;
        {
            uint256[] memory allowedChainIds = new uint256[](4);
            allowedChainIds[0] = block.chainid.toMoonbeamChainId();
            allowedChainIds[1] = block.chainid.toBaseChainId();
            allowedChainIds[2] = block.chainid.toOptimismChainId();
            allowedChainIds[3] = block.chainid.toEthereumChainId();

            addresses.addRestrictions(allowedChainIds);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory payloads
            ) = getTargetsPayloadsValues(addresses);

            {
                ProposalAction[] memory ethereumActions = actions.filter(
                    ActionType.Ethereum
                );
                address[] memory ethereumTargets = new address[](
                    ethereumActions.length
                );
                for (uint256 i = 0; i < ethereumActions.length; i++) {
                    ethereumTargets[i] = ethereumActions[i].target;
                }
                checkEthereumActions(addresses, ethereumTargets);
            }

            /// remove the restrictions
            addresses.removeRestriction();

            {
                ProposalAction[] memory moonbeamActions = actions.filter(
                    ActionType.Moonbeam
                );
                // Only touch the Moonbeam fork when there is something to
                // check. With Moonbeam wound down, fork id 0 may be the
                // placeholder stood up when its RPC is unreachable (see
                // ChainIds.createForksAndSelect), and selecting it would fail
                // checkMoonbeamActions' chain-id guard over an empty list.
                if (moonbeamActions.length > 0) {
                    vm.selectFork(MOONBEAM_FORK_ID);

                    address[] memory moonbeamTargets = new address[](
                        moonbeamActions.length
                    );
                    for (uint256 i = 0; i < moonbeamActions.length; i++) {
                        moonbeamTargets[i] = moonbeamActions[i].target;
                    }
                    checkMoonbeamActions(moonbeamTargets);
                }
            }

            vm.selectFork(BASE_FORK_ID);
            checkBaseOptimismActions(actions.filter(ActionType.Base));

            vm.selectFork(OPTIMISM_FORK_ID);
            checkBaseOptimismActions(actions.filter(ActionType.Optimism));

            vm.selectFork(ETHEREUM_FORK_ID);

            vm.roll(block.number + 1);
            /// VotingPowerAggregator uses timestamp-based voting — advance
            /// timestamp by 1 so the delegate checkpoint from a few statements
            /// above is visible to governor.propose() (which queries past
            /// voting power at block.timestamp - 1).
            vm.warp(block.timestamp + 1);

            /// triple check the values
            for (uint256 i = 0; i < targets.length; i++) {
                require(
                    targets[i] != address(0),
                    "Invalid target for governance"
                );
                require(
                    (payloads[i].length == 0 && values[i] > 0) ||
                        payloads[i].length > 0,
                    "Invalid arguments for governance"
                );
            }

            uint256 cost = governor.bridgeCostAll();
            vm.deal(caller, cost * 2);

            uint256[] memory splits = batchProposeSplits();

            if (splits.length == 0) {
                bytes memory proposeCalldata = abi.encodeWithSignature(
                    "propose(address[],uint256[],bytes[],string,bool)",
                    targets,
                    values,
                    payloads,
                    _proposeDescription(),
                    true // finalize = true
                );

                uint256 gasStart = gasleft();

                // Execute the proposal
                vm.prank(caller);
                (bool success, bytes memory returndata) = address(
                    payable(governorAddress)
                ).call{value: cost, gas: 52_000_000}(proposeCalldata);
                data = returndata;

                if (!success) {
                    _revertWithReturndata(
                        returndata,
                        "propose multichain governor v2 failed"
                    );
                }

                // single-call submission is one mainnet transaction and must
                // fit an Ethereum block with headroom
                require(
                    gasStart - gasleft() <= MAX_PROPOSE_CALL_GAS,
                    "Proposal propose gas limit exceeded"
                );
            } else {
                // batched submission: each call is checked against
                // MAX_PROPOSE_CALL_GAS individually inside
                // _submitGovernorCalls — the per-transaction limit is the
                // binding constraint, not the sum across transactions
                data = _submitBatchPropose(
                    governorAddress,
                    caller,
                    cost,
                    targets,
                    values,
                    payloads,
                    splits
                );
            }
        }

        uint256 proposalId = abi.decode(data, (uint256));

        // Roll to Active state (voting period)
        require(
            governor.state(proposalId) ==
                IMultichainGovernorV2.ProposalState.Active,
            "incorrect state, not active after proposing"
        );

        // Vote YES
        vm.prank(caller);
        governor.castVote(proposalId, 0);

        // Roll to allow proposal state transitions
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + 1 + governor.votingPeriod() + 1);

        require(
            governor.state(proposalId) ==
                IMultichainGovernorV2.ProposalState.CrossChainVoteCollection,
            "incorrect state, not CrossChainVoteCollection"
        );

        vm.warp(
            block.timestamp + governor.crossChainVoteCollectionPeriod() + 1
        );

        require(
            governor.state(proposalId) ==
                IMultichainGovernorV2.ProposalState.Succeeded,
            "incorrect state, not succeeded"
        );

        {
            address wormholeCoreEthereum = addresses.getAddress(
                "WORMHOLE_CORE",
                block.chainid.toEthereumChainId()
            );

            bytes[] memory temporalGovExecDataMoonbeam;
            bytes[] memory temporalGovExecDataBase;
            bytes[] memory temporalGovExecDataOptimism;

            if (actions.proposalActionTypeCount(ActionType.Moonbeam) != 0) {
                temporalGovExecDataMoonbeam = getTemporalGovPayloadsByChain(
                    addresses,
                    block.chainid.toMoonbeamChainId()
                );
            }

            if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
                temporalGovExecDataBase = getTemporalGovPayloadsByChain(
                    addresses,
                    block.chainid.toBaseChainId()
                );
            }

            if (actions.proposalActionTypeCount(ActionType.Optimism) != 0) {
                temporalGovExecDataOptimism = getTemporalGovPayloadsByChain(
                    addresses,
                    block.chainid.toOptimismChainId()
                );
            }

            vm.deal(caller, actions.sumEthereumValue());

            // Start recording logs to verify events after execution
            vm.recordLogs();

            uint256 gasStart = gasleft();

            // Execute the proposal
            vm.prank(caller);
            governor.execute{
                value: actions.sumEthereumValue(),
                gas: 52_000_000
            }(proposalId);

            require(
                gasStart - gasleft() <= 60_000_000,
                "Proposal execute gas limit exceeded"
            );

            // Verify LogMessagePublished events were emitted with correct payloads
            Vm.Log[] memory logs = vm.getRecordedLogs();

            _assertPayloadsPublished(
                logs,
                wormholeCoreEthereum,
                temporalGovExecDataMoonbeam,
                "Moonbeam"
            );
            _assertPayloadsPublished(
                logs,
                wormholeCoreEthereum,
                temporalGovExecDataBase,
                "Base"
            );
            _assertPayloadsPublished(
                logs,
                wormholeCoreEthereum,
                temporalGovExecDataOptimism,
                "Optimism"
            );
        }

        require(
            governor.state(proposalId) ==
                IMultichainGovernorV2.ProposalState.Executed,
            "Proposal state not executed"
        );

        _verifyMTokensPostRun();

        addresses.removeRestriction();
    }

    /// @notice run a chain's actions chunk by chunk in REVERSE chunk order.
    /// Chunks execute on the destination chain as independent temporal
    /// governor proposals with no ordering guarantee, so any hidden
    /// cross-chunk dependency (e.g. an earlier chunk funding a balance a
    /// later chunk spends) must make the simulation FAIL rather than pass by
    /// silently riding the build order. Single-chunk proposals (the default
    /// chunkCount of 1) execute exactly as before.
    function _runExtChainChunks(
        Addresses addresses,
        ActionType actionType
    ) internal {
        for (uint256 c = chunkCount(actionType); c > 0; c--) {
            _runExtChain(addresses, chunkActions(actionType, c - 1));
        }
    }

    /// @notice Runs the proposal actions on an external chain (Moonbeam, Base, Optimism)
    /// @param addresses the addresses contract
    /// @param proposalActions the actions to run
    function _runExtChain(
        Addresses addresses,
        ProposalAction[] memory proposalActions
    ) internal {
        require(proposalActions.length > 0, "Cannot run empty proposal");

        _verifyActionsPreRun(proposalActions);

        /// add restriction on external chain
        addresses.addRestriction(block.chainid);

        // Deploy the modified Wormhole Core implementation contract which
        // bypass the guardians signature check
        Implementation core = new Implementation();
        address wormhole = addresses.getAddress("WORMHOLE_CORE");

        /// Set the wormhole core address to have the
        /// runtime bytecode of the mock core
        vm.etch(wormhole, address(core).code);

        address[] memory targets = new address[](proposalActions.length);
        uint256[] memory values = new uint256[](proposalActions.length);
        bytes[] memory payloads = new bytes[](proposalActions.length);

        for (uint256 i = 0; i < proposalActions.length; i++) {
            targets[i] = proposalActions[i].target;
            values[i] = proposalActions[i].value;
            payloads[i] = proposalActions[i].data;
        }

        /// _runExtChain is invoked from three call sites — Moonbeam, Base,
        /// Optimism (lines 535/541/547). Each switches forks before calling.
        /// The target-has-code validation has to dispatch to the matching
        /// per-chain checker; calling checkBaseOptimismActions on Moonbeam
        /// reverts via ChainIds.nonMoonbeamChainIds().
        if (block.chainid.nonMoonbeamChainIds()) {
            checkBaseOptimismActions(proposalActions);
        } else {
            checkMoonbeamActions(targets);
        }

        bytes memory payload = abi.encode(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            targets,
            values,
            payloads
        );

        /// allow querying of Ethereum
        addresses.addRestriction(block.chainid.toEthereumChainId());

        bytes32 governor = addresses
            .getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY",
                block.chainid.toEthereumChainId()
            )
            .toBytes();

        /// disallow querying of Ethereum
        addresses.removeRestriction();

        bytes memory vaa = generateVAA(
            uint32(block.timestamp),
            /// Proposals originate from Ethereum (Wormhole chain ID 2)
            ETHEREUM_WORMHOLE_CHAIN_ID,
            governor,
            payload
        );

        ITemporalGovernor temporalGovernor = ITemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        temporalGovernor.queueProposal(vaa);

        vm.warp(block.timestamp + temporalGovernor.proposalDelay());

        temporalGovernor.executeProposal(vaa);

        _verifyMTokensPostRun();

        /// remove all restrictions placed in this function
        addresses.removeRestriction();
    }

    /// @dev utility function to generate a Wormhole VAA payload excluding the guardians signature
    function generateVAA(
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        bytes memory payload
    ) private view returns (bytes memory encodedVM) {
        uint64 sequence = 200;
        uint8 version = 1;

        encodedVM = abi.encodePacked(
            version,
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );
    }

    function getActionsByType(
        ActionType actionType
    ) public view returns (ProposalAction[] memory) {
        return actions.filter(actionType);
    }

    function getTemporalGovPayloadByChain(
        Addresses addresses,
        uint256 chainId
    ) public returns (bytes memory payload) {
        uint256 forkId = chainId.toForkId();
        ProposalAction[] memory proposalActions = actions.filter(
            _forkIdToActionType(forkId)
        );

        require(
            proposalActions.length > 0,
            string(
                abi.encodePacked(
                    "No actions found for chain %s",
                    chainId.chainIdToName()
                )
            )
        );

        address[] memory targets = new address[](proposalActions.length);
        uint256[] memory values = new uint256[](proposalActions.length);
        bytes[] memory calldatas = new bytes[](proposalActions.length);

        for (uint256 i = 0; i < proposalActions.length; i++) {
            targets[i] = proposalActions[i].target;
            values[i] = proposalActions[i].value;
            calldatas[i] = proposalActions[i].data;
        }

        addresses.addRestriction(chainId);
        payload = abi.encode(
            addresses.getAddress("TEMPORAL_GOVERNOR", chainId),
            targets,
            values,
            calldatas
        );
        addresses.removeRestriction();
    }

    /// @notice per-chunk temporal governor payloads for a chain: one element
    /// per chunkCount() chunk, a single element by default. Each element is
    /// the payload of one wormhole publishMessage call the governor makes
    /// for this chain during execute().
    function getTemporalGovPayloadsByChain(
        Addresses addresses,
        uint256 chainId
    ) public returns (bytes[] memory payloads) {
        ActionType actionType = _forkIdToActionType(chainId.toForkId());

        require(
            actions.proposalActionTypeCount(actionType) > 0,
            string(
                abi.encodePacked(
                    "No actions found for chain %s",
                    chainId.chainIdToName()
                )
            )
        );

        addresses.addRestriction(chainId);
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            chainId
        );
        addresses.removeRestriction();

        uint256 chunks = chunkCount(actionType);
        payloads = new bytes[](chunks);

        for (uint256 c = 0; c < chunks; c++) {
            ProposalAction[] memory chunk = chunkActions(actionType, c);
            require(chunk.length > 0, "empty action chunk");

            address[] memory targets = new address[](chunk.length);
            uint256[] memory values = new uint256[](chunk.length);
            bytes[] memory calldatas = new bytes[](chunk.length);

            for (uint256 i = 0; i < chunk.length; i++) {
                targets[i] = chunk[i].target;
                values[i] = chunk[i].value;
                calldatas[i] = chunk[i].data;
            }

            payloads[c] = abi.encode(
                temporalGovernor,
                targets,
                values,
                calldatas
            );
        }
    }

    /// @notice asserts every expected temporal governor payload for a chain
    /// was published from the wormhole core during proposal execution
    function _assertPayloadsPublished(
        Vm.Log[] memory logs,
        address wormholeCore,
        bytes[] memory expectedPayloads,
        string memory chainName
    ) internal pure {
        bytes32 sig = keccak256(
            "LogMessagePublished(address,uint64,uint32,bytes,uint8)"
        );

        for (uint256 i = 0; i < expectedPayloads.length; i++) {
            bool seen = false;
            for (uint256 k = 0; k < logs.length; k++) {
                if (
                    logs[k].emitter == wormholeCore &&
                    logs[k].topics.length > 0 &&
                    logs[k].topics[0] == sig
                ) {
                    (, , bytes memory payload, ) = abi.decode(
                        logs[k].data,
                        (uint64, uint32, bytes, uint8)
                    );

                    if (keccak256(payload) == keccak256(expectedPayloads[i])) {
                        seen = true;
                        break;
                    }
                }
            }
            assertTrue(
                seen,
                string(
                    abi.encodePacked(
                        "Missing LogMessagePublished event for ",
                        chainName
                    )
                )
            );
        }
    }
}

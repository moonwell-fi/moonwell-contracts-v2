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

    /// @notice instant finality https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint8 public constant consistencyLevel = 200;

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

    /// @notice hex encoded description of the proposal
    bytes public PROPOSAL_DESCRIPTION;

    /// @notice allows asserting wormhole core correctly emits data to temporal governor
    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    /// @notice set the governance proposal's description
    function _setProposalDescription(
        bytes memory newProposalDescription
    ) internal {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

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
        require(fork <= 3, "Invalid active fork");
        _pushAction(target, 0, data, description, ActionType(fork));
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

    /// @notice returns the total number of actions in the proposal
    /// including moonbeam, base and optimism actions which are each bundled into a
    /// single action to wormhole core on Ethereum.
    function allActionTypesCount() public view returns (uint256 count) {
        uint256 moonbeamActions = actions.proposalActionTypeCount(
            ActionType.Moonbeam
        );
        moonbeamActions = moonbeamActions > 0 ? 1 : 0;

        uint256 baseActions = actions.proposalActionTypeCount(ActionType.Base);
        baseActions = baseActions > 0 ? 1 : 0;

        uint256 optimismActions = actions.proposalActionTypeCount(
            ActionType.Optimism
        );
        optimismActions = optimismActions > 0 ? 1 : 0;

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
            targets[currIndex] = wormholeCore;
            values[currIndex] = 0;
            payloads[currIndex] = getTemporalGovCalldata(
                temporalGovernorMoonbeam,
                actions.filter(ActionType.Moonbeam)
            );
            currIndex++;
        }

        /// only get temporal governor calldata if there are actions to execute on Base
        if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
            targets[currIndex] = wormholeCore;
            values[currIndex] = 0;
            payloads[currIndex] = getTemporalGovCalldata(
                temporalGovernorBase,
                actions.filter(ActionType.Base)
            );
            currIndex++;
        }

        /// only get temporal governor calldata if there are actions to execute on Optimism
        if (
            temporalGovernorOptimism != address(0) &&
            actions.proposalActionTypeCount(ActionType.Optimism) != 0
        ) {
            targets[currIndex] = wormholeCore;
            values[currIndex] = 0;
            payloads[currIndex] = getTemporalGovCalldata(
                temporalGovernorOptimism,
                actions.filter(ActionType.Optimism)
            );
            currIndex++;
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
            bytes(PROPOSAL_DESCRIPTION).length > 0,
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
            string(PROPOSAL_DESCRIPTION),
            true // finalize = true
        );

        return proposalCalldata;
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
    }

    function deploy(Addresses, address) public virtual override {}

    function afterDeploy(Addresses, address) public virtual override {}

    function build(Addresses) public virtual override {}

    function teardown(Addresses, address) public virtual override {}

    function run(
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
            _runExtChain(addresses, actions.filter(ActionType.Moonbeam));
        }

        if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
            vm.selectFork(BASE_FORK_ID);
            vm.warp(blockTimestamp);
            _runExtChain(addresses, actions.filter(ActionType.Base));
        }

        if (actions.proposalActionTypeCount(ActionType.Optimism) != 0) {
            vm.selectFork(OPTIMISM_FORK_ID);
            vm.warp(blockTimestamp);
            _runExtChain(addresses, actions.filter(ActionType.Optimism));
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

            checkEthereumActions(targets);

            /// remove the restrictions
            addresses.removeRestriction();

            vm.selectFork(MOONBEAM_FORK_ID);
            checkBaseOptimismActions(actions.filter(ActionType.Moonbeam));

            vm.selectFork(BASE_FORK_ID);
            checkBaseOptimismActions(actions.filter(ActionType.Base));

            vm.selectFork(OPTIMISM_FORK_ID);
            checkBaseOptimismActions(actions.filter(ActionType.Optimism));

            vm.selectFork(ETHEREUM_FORK_ID);

            vm.roll(block.number + 1);

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

            bytes memory proposeCalldata = abi.encodeWithSignature(
                "propose(address[],uint256[],bytes[],string,bool)",
                targets,
                values,
                payloads,
                string(PROPOSAL_DESCRIPTION),
                true // finalize = true
            );

            uint256 cost = governor.bridgeCostAll();
            vm.deal(caller, cost * 2);

            uint256 gasStart = gasleft();

            // Execute the proposal
            vm.prank(caller);
            (bool success, bytes memory returndata) = address(
                payable(governorAddress)
            ).call{value: cost, gas: 52_000_000}(proposeCalldata);
            data = returndata;

            require(success, "propose multichain governor v2 failed");

            require(
                gasStart - gasleft() <= 60_000_000,
                "Proposal propose gas limit exceeded"
            );
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

            bytes memory temporalGovExecDataMoonbeam;
            bytes memory temporalGovExecDataBase;
            bytes memory temporalGovExecDataOptimism;

            if (actions.proposalActionTypeCount(ActionType.Moonbeam) != 0) {
                temporalGovExecDataMoonbeam = getTemporalGovPayloadByChain(
                    addresses,
                    block.chainid.toMoonbeamChainId()
                );
            }

            if (actions.proposalActionTypeCount(ActionType.Base) != 0) {
                temporalGovExecDataBase = getTemporalGovPayloadByChain(
                    addresses,
                    block.chainid.toBaseChainId()
                );
            }

            if (actions.proposalActionTypeCount(ActionType.Optimism) != 0) {
                temporalGovExecDataOptimism = getTemporalGovPayloadByChain(
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
            bytes32 sig = keccak256(
                "LogMessagePublished(address,uint64,uint32,bytes,uint8)"
            );

            if (temporalGovExecDataMoonbeam.length != 0) {
                bool seenMoonbeam = false;
                for (uint256 k = 0; k < logs.length; k++) {
                    if (
                        logs[k].emitter == wormholeCoreEthereum &&
                        logs[k].topics.length > 0 &&
                        logs[k].topics[0] == sig
                    ) {
                        (
                            uint64 sequence,
                            uint32 nonce2,
                            bytes memory payload,
                            uint8 cl
                        ) = abi.decode(
                                logs[k].data,
                                (uint64, uint32, bytes, uint8)
                            );
                        sequence;
                        nonce2;
                        cl;

                        if (
                            keccak256(payload) ==
                            keccak256(temporalGovExecDataMoonbeam)
                        ) {
                            seenMoonbeam = true;
                            break;
                        }
                    }
                }
                assertTrue(
                    seenMoonbeam,
                    "Missing LogMessagePublished event for Moonbeam"
                );
            }

            if (temporalGovExecDataBase.length != 0) {
                bool seenBase = false;
                for (uint256 k = 0; k < logs.length; k++) {
                    if (
                        logs[k].emitter == wormholeCoreEthereum &&
                        logs[k].topics.length > 0 &&
                        logs[k].topics[0] == sig
                    ) {
                        (
                            uint64 sequence,
                            uint32 nonce2,
                            bytes memory payload,
                            uint8 cl
                        ) = abi.decode(
                                logs[k].data,
                                (uint64, uint32, bytes, uint8)
                            );
                        sequence;
                        nonce2;
                        cl;

                        if (
                            keccak256(payload) ==
                            keccak256(temporalGovExecDataBase)
                        ) {
                            seenBase = true;
                            break;
                        }
                    }
                }
                assertTrue(
                    seenBase,
                    "Missing LogMessagePublished event for Base"
                );
            }

            if (temporalGovExecDataOptimism.length != 0) {
                bool seenOptimism = false;
                for (uint256 k = 0; k < logs.length; k++) {
                    if (
                        logs[k].emitter == wormholeCoreEthereum &&
                        logs[k].topics.length > 0 &&
                        logs[k].topics[0] == sig
                    ) {
                        (
                            uint64 sequence,
                            uint32 nonce2,
                            bytes memory payload,
                            uint8 cl
                        ) = abi.decode(
                                logs[k].data,
                                (uint64, uint32, bytes, uint8)
                            );
                        sequence;
                        nonce2;
                        cl;

                        if (
                            keccak256(payload) ==
                            keccak256(temporalGovExecDataOptimism)
                        ) {
                            seenOptimism = true;
                            break;
                        }
                    }
                }
                assertTrue(
                    seenOptimism,
                    "Missing LogMessagePublished event for Optimism"
                );
            }
        }

        require(
            governor.state(proposalId) ==
                IMultichainGovernorV2.ProposalState.Executed,
            "Proposal state not executed"
        );

        _verifyMTokensPostRun();

        addresses.removeRestriction();
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

        checkBaseOptimismActions(proposalActions);

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
            ActionType(forkId)
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
}

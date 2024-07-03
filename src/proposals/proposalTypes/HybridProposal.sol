//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20Votes} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";

import "@forge-std/Test.sol";

import "@protocol/utils/Constants.sol";

import {ForkID} from "@utils/Enums.sol";
import {Address} from "@utils/Address.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {ChainIdHelper} from "@protocol/utils/ChainIdHelper.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {ITemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {MarketCreationHook} from "@proposals/hooks/MarketCreationHook.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

/// @notice this is a proposal type to be used for proposals that
/// require actions to be taken on both moonbeam and base.
/// This is a bit wonky because we are trying to simulate
/// what happens on two different networks. So we need to have
/// two different proposal types. One for moonbeam and one for base.
/// We also need to have references to both networks in the proposal
/// to switch between forks.
abstract contract HybridProposal is
    ChainIds,
    Proposal,
    ProposalChecker,
    MarketCreationHook
{
    using Strings for string;
    using Address for address;

    /// @notice nonce for wormhole, unused by Temporal Governor
    uint32 public nonce = 0;

    /// @notice instant finality on moonbeam https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint8 public constant consistencyLevel = 200;

    /// @notice actions to run against contracts live on moonbeam
    ProposalAction[] public moonbeamActions;

    /// @notice actions to run against contracts live on base
    ProposalAction[] public baseActions;

    /// @notice actions to run against contracts live on optimism
    ProposalAction[] public optimismActions;

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
        require(fork <= 2, "Invalid active fork");
        _pushAction(target, 0, data, description, ForkID(fork));
    }

    /// @notice push an action to the Hybrid proposal
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param proposalType whether this action is on moonbeam or base
    function _pushAction(
        address target,
        bytes memory data,
        string memory description,
        ForkID proposalType
    ) internal {
        _pushAction(target, 0, data, description, proposalType);
    }

    /// @notice push an action to the Hybrid proposal
    /// @param target the target contract
    /// @param value msg.value to send to target
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param proposalType which chain this proposal action belongs to
    function _pushAction(
        address target,
        uint256 value,
        bytes memory data,
        string memory description,
        ForkID proposalType
    ) internal {
        if (proposalType == ActionType.Moonbeam) {
            moonbeamActions.push(
                ProposalAction({
                    target: target,
                    value: value,
                    data: data,
                    description: description
                })
            );
        } else if (proposalType == ActionType.Base) {
            baseActions.push(
                ProposalAction({
                    target: target,
                    value: value,
                    data: data,
                    description: description
                })
            );
        } else if (proposalType == ActionType.Optimism) {
            optimismActions.push(
                ProposalAction({
                    target: target,
                    value: value,
                    data: data,
                    description: description
                })
            );
        } else {
            revert(
                string(
                    abi.encodePacked(
                        "Proposal type not found for ",
                        description
                    )
                )
            );
        }
    }

    /// @notice push an action to the Hybrid proposal with 0 value and no description
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param proposalType which chain this proposal action belongs to
    function _pushAction(
        address target,
        bytes memory data,
        ForkID proposalType
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
            ForkID[] memory,
            string[] memory
        )
    {
        address[] memory targets = new address[](
            moonbeamActions.length + baseActions.length + optimismActions.length
        );

        uint256[] memory values = new uint256[](
            moonbeamActions.length + baseActions.length + optimismActions.length
        );

        bytes[] memory calldatas = new bytes[](
            moonbeamActions.length + baseActions.length + optimismActions.length
        );

        ForkID[] memory network = new ForkID[](
            moonbeamActions.length + baseActions.length + optimismActions.length
        );

        string[] memory descriptions = new string[](
            moonbeamActions.length + baseActions.length + optimismActions.length
        );

        /// moonbeam actions
        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            targets[i] = moonbeamActions[i].target;
            values[i] = moonbeamActions[i].value;
            calldatas[i] = moonbeamActions[i].data;
            descriptions[i] = moonbeamActions[i].description;
            network[i] = ActionType.Moonbeam;
        }

        /// base actions
        uint256 indexStart = moonbeamActions.length;
        for (uint256 i = 0; i < baseActions.length; i++) {
            targets[i + indexStart] = baseActions[i].target;
            values[i + indexStart] = baseActions[i].value;
            calldatas[i + indexStart] = baseActions[i].data;
            descriptions[i + indexStart] = baseActions[i].description;
            network[i + indexStart] = ActionType.Base;
        }

        /// optimism actions, start where base actions left off
        indexStart += baseActions.length;
        for (uint256 i = 0; i < optimismActions.length; i++) {
            targets[i + indexStart] = optimismActions[i].target;
            values[i + indexStart] = optimismActions[i].value;
            calldatas[i + indexStart] = optimismActions[i].data;
            descriptions[i + indexStart] = optimismActions[i].description;
            network[i + indexStart] = ActionType.Optimism;
        }

        return (targets, values, calldatas, network, descriptions);
    }

    function getTemporalGovCalldata(
        address temporalGovernor,
        ProposalAction[] memory actions
    ) public view returns (bytes memory timelockCalldata) {
        require(
            temporalGovernor != address(0),
            "getTemporalGovCalldata: Invalid temporal governor"
        );

        address[] memory targets = new address[](actions.length);
        uint256[] memory values = new uint256[](actions.length);
        bytes[] memory payloads = new bytes[](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            payloads[i] = actions[i].data;
        }

        timelockCalldata = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            nonce,
            abi.encode(temporalGovernor, targets, values, payloads),
            consistencyLevel
        );

        require(
            timelockCalldata.length <= 25_000,
            "getTemporalGovCalldata: Timelock publish message calldata max size of 25kb exceeded"
        );
    }

    /// @notice return arrays of all items in the proposal that the
    /// temporal governor will receive
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues(
        Addresses addresses
    )
        public
        view
        override
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        address temporalGovernorBase = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            ChainIdHelper.toBaseChainId(block.chainid)
        );
        address temporalGovernorOptimism = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            ChainIdHelper.toOptimismChainId(block.chainid)
        );

        return
            getTargetsPayloadsValues(
                addresses.getAddress(
                    "WORMHOLE_CORE",
                    ChainIdHelper.toMoonbeamChainId(block.chainid)
                ),
                temporalGovernorBase,
                temporalGovernorOptimism
            );
    }

    ///
    /// ------------------------------------------
    ///   Governance Proposal Calldata Structure
    /// ------------------------------------------
    ///
    /// - Moonbeam Actions:
    ///  - actions whose target chain are non wormhole moonbeam smart contracts
    ///  this could be a risk recommendation to the moonbeam chain
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
    /// temporal governor will receive
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues(
        address wormholeCore,
        address temporalGovernorBase,
        address temporalGovernorOptimism
    ) public view returns (address[] memory, uint256[] memory, bytes[] memory) {
        uint256 proposalLength = moonbeamActions.length;

        if (baseActions.length != 0) {
            proposalLength += 1;
        }

        if (optimismActions.length != 0) {
            proposalLength += 1;
        }

        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        uint256 currIndex = 0;
        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            /// target cannot be address 0 as that call will fail
            require(
                moonbeamActions[i].target != address(0),
                "Invalid target for governance"
            );

            /// value can be 0
            /// arguments can be 0 as long as eth is sent
            /// if there are no args and no eth, the action is not valid
            require(
                (moonbeamActions[i].data.length == 0 &&
                    moonbeamActions[i].value > 0) ||
                    moonbeamActions[i].data.length > 0,
                "Invalid arguments for governance"
            );

            targets[i] = moonbeamActions[i].target;
            values[i] = moonbeamActions[i].value;
            payloads[i] = moonbeamActions[i].data;

            currIndex++;
        }

        /// only get temporal governor calldata if there are actions to execute on base
        if (baseActions.length != 0) {
            /// fill out final piece of proposal which is the call
            /// to publishMessage on the temporal governor
            targets[currIndex] = wormholeCore;
            values[currIndex] = 0;
            payloads[currIndex] = getTemporalGovCalldata(
                temporalGovernorBase,
                baseActions
            );
            currIndex++;
        }

        /// only get temporal governor calldata if there are actions to execute on optimism
        if (optimismActions.length != 0) {
            /// fill out final piece of proposal which is the call
            /// to publishMessage on the temporal governor
            targets[currIndex] = wormholeCore;
            values[currIndex] = 0;
            payloads[currIndex] = getTemporalGovCalldata(
                temporalGovernorOptimism,
                optimismActions
            );
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
            "\n\nProposal Description:\n\n%s",
            string(PROPOSAL_DESCRIPTION)
        );

        console.log(
            "\n\n------------------ Proposal Actions ------------------"
        );

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ForkID[] memory network,
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
                chainForkToName[uint256(network[i])]
            );

            console.log("\n");
        }
    }

    /// @notice Getter function for `GovernorBravoDelegate.propose()` calldata
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
            "propose(address[],uint256[],bytes[],string)",
            targets,
            values,
            payloads,
            string(PROPOSAL_DESCRIPTION)
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
        console.log("Governor multichain proposal calldata");
        console.logBytes(getCalldata(addresses));
    }

    function deploy(Addresses, address) public virtual override {}

    function afterDeploy(Addresses, address) public virtual override {}

    function preBuildMock(Addresses) public virtual override {}

    function build(Addresses) public virtual override {}

    function teardown(Addresses, address) public virtual override {}

    function run(Addresses addresses, address) public virtual override {
        vm.selectFork(uint256(ActionType.Moonbeam));
        _runMoonbeamMultichainGovernor(
            addresses,
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        if (baseActions.length != 0) {
            vm.selectFork(uint256(ActionType.Base));
            _runExtChain(addresses, baseActions);
        }

        if (optimismActions.length != 0) {
            vm.selectFork(uint256(ActionType.Optimism));
            _runExtChain(addresses, optimismActions);
        }

        vm.selectFork(uint256(primaryForkId()));
    }

    /// @notice search for a on-chain proposal that matches the proposal calldata
    /// @param addresses the addresses contract
    /// @param governor the governor address
    /// @return proposalId the proposal id, 0 if no proposal is found
    function getProposalId(
        Addresses addresses,
        address governor
    ) public override returns (uint256 proposalId) {
        vm.selectFork(uint256(ActionType.Moonbeam));

        uint256 proposalCount = onchainProposalId != 0
            ? onchainProposalId
            : MultichainGovernor(governor).proposalCount();
        bytes memory proposalCalldata = getCalldata(addresses);

        // Loop through all proposals to find the one that matches
        // Start from the latest proposal as it is more likely to be the one
        while (proposalCount > 0) {
            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = MultichainGovernor(governor).getProposalData(proposalCount);

            bytes memory onchainCalldata = abi.encodeWithSignature(
                "propose(address[],uint256[],bytes[],string)",
                targets,
                values,
                calldatas,
                PROPOSAL_DESCRIPTION
            );

            if (keccak256(proposalCalldata) == keccak256(onchainCalldata)) {
                proposalId = proposalCount;
                break;
            }

            proposalCount--;
        }

        vm.selectFork(uint256(primaryForkId()));
    }

    /// @notice Runs the proposal on moonbeam, verifying the actions through the hook
    /// @param addresses the addresses contract
    /// @param caller the proposer address
    function _runMoonbeamMultichainGovernor(
        Addresses addresses,
        address caller
    ) internal {
        _verifyActionsPreRun(moonbeamActions);

        bool disallowMoonbeam;

        if (!addresses.chainIdAllowed(block.chainid)) {
            addresses.addRestriction(block.chainid);
            disallowMoonbeam = true;
        }

        address governanceToken = addresses.getAddress("GOVTOKEN");
        address governorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        MultichainGovernor governor = MultichainGovernor(governorAddress);

        {
            // Ensure proposer meets minimum proposal threshold and quorum votes to pass the proposal
            uint256 quorumVotes = governor.quorum();
            uint256 proposalThreshold = governor.proposalThreshold();
            uint256 votingPower = quorumVotes > proposalThreshold
                ? quorumVotes
                : proposalThreshold;
            deal(governanceToken, caller, votingPower);

            // Delegate proposer's votes to itself
            vm.prank(caller);
            ERC20Votes(governanceToken).delegate(caller);
        }

        bytes memory data;
        {
            uint256[] memory allowedChainIds = new uint256[](3);
            allowedChainIds[0] = ChainIdHelper.toBaseChainId(block.chainid);
            allowedChainIds[1] = ChainIdHelper.toOptimismChainId(block.chainid);
            allowedChainIds[2] = ChainIdHelper.toMoonbeamChainId(block.chainid);

            addresses.addRestrictions(allowedChainIds);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory payloads
            ) = getTargetsPayloadsValues(addresses);

            checkMoonbeamActions(targets);

            /// remove the Moonbeam, Base and Optimism restriction
            addresses.removeRestriction();

            vm.selectFork(uint256(ActionType.Base));
            checkBaseOptimismActions(baseActions);

            vm.selectFork(uint256(ActionType.Optimism));
            checkBaseOptimismActions(optimismActions);

            vm.selectFork(uint256(ActionType.Moonbeam));

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
                "propose(address[],uint256[],bytes[],string)",
                targets,
                values,
                payloads,
                string(PROPOSAL_DESCRIPTION)
            );

            uint256 cost = governor.bridgeCostAll();
            vm.deal(caller, cost * 2);

            // Execute the proposal
            uint256 gasStart = gasleft();
            vm.prank(caller);
            (bool success, bytes memory returndata) = address(
                payable(governorAddress)
            ).call{value: cost}(proposeCalldata);
            data = returndata;

            require(success, "propose multichain governor failed");

            require(
                gasStart - gasleft() <= 13_000_000,
                "Proposal propose gas limit exceeded"
            );
        }

        uint256 proposalId = abi.decode(data, (uint256));

        // Roll to Active state (voting period)
        require(
            governor.state(proposalId) ==
                IMultichainGovernor.ProposalState.Active,
            "incorrect state, not active after proposing"
        );

        // Vote YES
        vm.prank(caller);
        governor.castVote(proposalId, 0);

        // Roll to allow proposal state transitions
        vm.roll(block.number + governor.votingPeriod() + 1);
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        require(
            governor.state(proposalId) ==
                IMultichainGovernor.ProposalState.CrossChainVoteCollection,
            "incorrect state, not succeeded"
        );

        vm.warp(
            block.timestamp + governor.crossChainVoteCollectionPeriod() + 1
        );

        require(
            governor.state(proposalId) ==
                IMultichainGovernor.ProposalState.Succeeded,
            "incorrect state, not succeeded"
        );

        {
            address wormholeCoreMoonbeam = addresses.getAddress(
                "WORMHOLE_CORE",
                ChainIdHelper.toMoonbeamChainId(block.chainid)
            );

            {
                if (baseActions.length != 0) {
                    address[] memory targets = new address[](
                        baseActions.length
                    );
                    uint256[] memory values = new uint256[](baseActions.length);
                    bytes[] memory calldatas = new bytes[](baseActions.length);

                    for (uint256 i = 0; i < baseActions.length; i++) {
                        targets[i] = baseActions[i].target;
                        values[i] = baseActions[i].value;
                        calldatas[i] = baseActions[i].data;
                    }

                    addresses.addRestriction(
                        ChainIdHelper.toBaseChainId(block.chainid)
                    );
                    address temporalGov = addresses.getAddress(
                        "TEMPORAL_GOVERNOR",
                        ChainIdHelper.toBaseChainId(block.chainid)
                    );
                    addresses.removeRestriction();

                    bytes memory temporalGovExecData = abi.encode(
                        temporalGov,
                        targets,
                        values,
                        calldatas
                    );

                    /// increments each time the Multichain Governor publishes a message
                    uint64 nextSequence = IWormhole(wormholeCoreMoonbeam)
                        .nextSequence(address(governor));

                    /// expect emitting of events to Wormhole Core on Moonbeam if Base actions exist
                    vm.expectEmit(true, true, true, true, wormholeCoreMoonbeam);

                    /// event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
                    emit LogMessagePublished(
                        address(governor),
                        nextSequence,
                        nonce, /// nonce is hardcoded at 0 in HybridProposal.sol
                        temporalGovExecData,
                        consistencyLevel /// consistency level is hardcoded at 200 in HybridProposal.sol
                    );
                }
            }

            {
                if (optimismActions.length != 0) {
                    address[] memory targets = new address[](
                        optimismActions.length
                    );
                    uint256[] memory values = new uint256[](
                        optimismActions.length
                    );
                    bytes[] memory calldatas = new bytes[](
                        optimismActions.length
                    );

                    for (uint256 i = 0; i < optimismActions.length; i++) {
                        targets[i] = optimismActions[i].target;
                        values[i] = optimismActions[i].value;
                        calldatas[i] = optimismActions[i].data;
                    }

                    addresses.addRestriction(
                        ChainIdHelper.toOptimismChainId(block.chainid)
                    );
                    address temporalGov = addresses.getAddress(
                        "TEMPORAL_GOVERNOR",
                        ChainIdHelper.toOptimismChainId(block.chainid)
                    );
                    addresses.removeRestriction();

                    bytes memory temporalGovExecData = abi.encode(
                        temporalGov,
                        targets,
                        values,
                        calldatas
                    );

                    /// increments each time the Multichain Governor publishes a message
                    uint64 nextSequence = IWormhole(wormholeCoreMoonbeam)
                        .nextSequence(address(governor));

                    if (baseActions.length > 0) {
                        nextSequence++;
                    }

                    /// expect emitting of events to Wormhole Core on Moonbeam if Base actions exist
                    vm.expectEmit(true, true, true, true, wormholeCoreMoonbeam);

                    /// event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
                    emit LogMessagePublished(
                        address(governor),
                        nextSequence,
                        nonce, /// nonce is hardcoded at 0 in HybridProposal.sol
                        temporalGovExecData,
                        consistencyLevel /// consistency level is hardcoded at 200 in HybridProposal.sol
                    );
                }
            }

            uint256 gasStart = gasleft();

            /// Execute the proposal
            governor.execute(proposalId);

            require(
                gasStart - gasleft() <= 13_000_000,
                "Proposal execute gas limit exceeded"
            );
        }

        require(
            governor.state(proposalId) ==
                IMultichainGovernor.ProposalState.Executed,
            "Proposal state not executed"
        );

        _verifyMTokensPostRun();

        addresses.removeRestriction();
    }

    /// TODO find a way to either make this function generic, or find a way to
    /// make a second function to do the same thing for optimism.
    /// for cleanliness prefer generic implementation and think through this.

    /// @notice Runs the proposal actions on base, verifying the actions through the hook
    /// @param addresses the addresses contract
    /// @param actions the actions to verify
    function _runExtChain(
        Addresses addresses,
        ProposalAction[] memory actions
    ) internal {
        _verifyActionsPreRun(actions);

        /// add restriction on external chain
        addresses.addRestriction(block.chainid);

        // Deploy the modified Wormhole Core implementation contract which
        // bypass the guardians signature check
        Implementation core = new Implementation();
        address wormhole = addresses.getAddress("WORMHOLE_CORE");

        /// Set the wormhole core address to have the
        /// runtime bytecode of the mock core
        vm.etch(wormhole, address(core).code);

        address[] memory targets = new address[](actions.length);
        uint256[] memory values = new uint256[](actions.length);
        bytes[] memory payloads = new bytes[](actions.length);

        for (uint256 i = 0; i < actions.length; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            payloads[i] = actions[i].data;
        }

        checkBaseOptimismActions(actions);

        bytes memory payload = abi.encode(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            targets,
            values,
            payloads
        );

        /// allow querying of Moonbeam
        addresses.addRestriction(
            ChainIdHelper.toMoonbeamChainId(block.chainid)
        );

        bytes32 governor = addresses
            .getAddress(
                "MULTICHAIN_GOVERNOR_PROXY",
                ChainIdHelper.toMoonbeamChainId(block.chainid)
            )
            .toBytes();

        /// disallow querying of Moonbeam
        addresses.removeRestriction();

        bytes memory vaa = generateVAA(
            uint32(block.timestamp),
            /// we can hardcode this wormhole chainID because all proposals
            /// should come from Moonbeam
            moonBeamWormholeChainId,
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

    /// TODO replace this throughout the repo with a better simulation method

    /// @notice simulate cross chain proposal
    /// @param temporalGovAddress address of the cross chain governor executing the calls
    /// run pre and post proposal hooks to ensure that mToken markets created by the
    /// proposal are valid and mint at least 1 wei worth of mTokens to address 0
    function _simulateCrossChainActions(
        Addresses addresses,
        address temporalGovAddress
    ) internal {
        (address[] memory targets, , ) = getTargetsPayloadsValues(addresses);

        vm.selectFork(uint256(ActionType.Moonbeam));
        checkMoonbeamActions(targets);

        vm.selectFork(uint256(ActionType.Base));
        checkBaseOptimismActions(baseActions);

        require(targets.length == 1);

        _verifyActionsPreRun(baseActions);
        _simulateMultisigActions(temporalGovAddress, baseActions);
        _verifyMTokensPostRun();
    }

    /// TODO get rid of this
    /// @notice simulate multisig proposal
    /// @param multisigAddress address of the multisig doing the calls
    function _simulateMultisigActions(
        address multisigAddress,
        ProposalAction[] memory actions
    ) internal {
        vm.startPrank(multisigAddress);

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = actions[i].target.call{
                value: actions[i].value
            }(actions[i].data);

            require(success, string(result));
        }

        vm.stopPrank();
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
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Address} from "@openzeppelin-contracts/contracts/utils/Address.sol";
import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/governance/deprecated/Well.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IHybridProposal} from "@proposals/proposalTypes/IHybridProposal.sol";
import {MarketCreationHook} from "@proposals/hooks/MarketCreationHook.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichainGovernor/MultichainGovernor.sol";
import {IMultichainProposal} from "@proposals/proposalTypes/IMultichainProposal.sol";
import {IArtemisGovernor} from "@protocol/governance/IArtemisGovernor.sol";

/// @notice this is a proposal type to be used for proposals that
/// require actions to be taken on both moonbeam and base.
/// This is a bit wonky because we are trying to simulate
/// what happens on two different networks. So we need to have
/// two different proposal types. One for moonbeam and one for base.
/// We also need to have references to both networks in the proposal
/// to switch between forks.

abstract contract HybridProposal is
    IHybridProposal,
    IMultichainProposal,
    MarketCreationHook,
    Proposal,
    ChainIds
{
    using Strings for *;
    using Address for address;

    /// @notice nonce for wormhole, unused by Temporal Governor
    uint32 private constant nonce = 0;

    /// @notice instant finality on moonbeam https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint16 public constant consistencyLevel = 200;

    /// @notice actions to run against contracts live on moonbeam
    ProposalAction[] public moonbeamActions;

    /// @notice actions to run against contracts live on base
    ProposalAction[] public baseActions;

    /// @notice hex encoded description of the proposal
    bytes public PROPOSAL_DESCRIPTION;

    string public constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    /// @notice fork ID for base
    uint256 public baseForkId =
        vm.createFork(vm.envOr("BASE_RPC_URL", DEFAULT_BASE_RPC_URL));

    string public constant DEFAULT_MOONBEAM_RPC_URL =
        "https://rpc.api.moonbeam.network";

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envOr("MOONBEAM_RPC_URL", DEFAULT_MOONBEAM_RPC_URL));

    /// @notice set the governance proposal's description
    function _setProposalDescription(
        bytes memory newProposalDescription
    ) internal {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

    /// @notice push an action to the Hybrid proposal
    /// @param target the target contract
    /// @param value msg.value to send to target
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param isMoonbeam whether this action is on moonbeam or base
    function _pushHybridAction(
        address target,
        uint256 value,
        bytes memory data,
        string memory description,
        bool isMoonbeam
    ) internal {
        if (isMoonbeam) {
            moonbeamActions.push(
                ProposalAction({
                    target: target,
                    value: value,
                    data: data,
                    description: description
                })
            );
        } else {
            baseActions.push(
                ProposalAction({
                    target: target,
                    value: value,
                    data: data,
                    description: description
                })
            );
        }
    }

    /// @notice push an action to the Hybrid proposal with 0 value
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param description description of the action
    /// @param isMoonbeam whether this action is on moonbeam or base
    function _pushHybridAction(
        address target,
        bytes memory data,
        string memory description,
        bool isMoonbeam
    ) internal {
        _pushHybridAction(target, 0, data, description, isMoonbeam);
    }

    /// @notice push an action to the Hybrid proposal with 0 value and no description
    /// @param target the target contract
    /// @param data calldata to pass to the target
    /// @param isMoonbeam whether this action is on moonbeam or base
    function _pushHybridAction(
        address target,
        bytes memory data,
        bool isMoonbeam
    ) internal {
        _pushHybridAction(target, 0, data, "", isMoonbeam);
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
            bool[] memory,
            string[] memory
        )
    {
        address[] memory targets = new address[](
            moonbeamActions.length + baseActions.length
        );
        uint256[] memory values = new uint256[](
            moonbeamActions.length + baseActions.length
        );
        bytes[] memory calldatas = new bytes[](
            moonbeamActions.length + baseActions.length
        );
        bool[] memory isMoonbeam = new bool[](
            moonbeamActions.length + baseActions.length
        );
        string[] memory descriptions = new string[](
            moonbeamActions.length + baseActions.length
        );

        /// moonbeam actions
        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            targets[i] = moonbeamActions[i].target;
            values[i] = moonbeamActions[i].value;
            calldatas[i] = moonbeamActions[i].data;
            descriptions[i] = moonbeamActions[i].description;
            isMoonbeam[i] = true;
        }

        /// base actions
        uint256 indexStart = moonbeamActions.length;
        for (uint256 i = 0; i < baseActions.length; i++) {
            targets[i + indexStart] = baseActions[i].target;
            values[i + indexStart] = baseActions[i].value;
            calldatas[i + indexStart] = baseActions[i].data;
            descriptions[i + indexStart] = baseActions[i].description;
            isMoonbeam[i + indexStart] = false;
        }

        return (targets, values, calldatas, isMoonbeam, descriptions);
    }

    function getTemporalGovCalldata(
        address temporalGovernor
    ) public view returns (bytes memory timelockCalldata) {
        require(
            temporalGovernor != address(0),
            "getTemporalGovCalldata: Invalid temporal governor"
        );

        address[] memory targets = new address[](baseActions.length);
        uint256[] memory values = new uint256[](baseActions.length);
        bytes[] memory payloads = new bytes[](baseActions.length);

        for (uint256 i = 0; i < baseActions.length; i++) {
            targets[i] = baseActions[i].target;
            values[i] = baseActions[i].value;
            payloads[i] = baseActions[i].data;
        }

        timelockCalldata = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            nonce,
            abi.encode(temporalGovernor, targets, values, payloads),
            consistencyLevel
        );

        require(
            timelockCalldata.length <= 10_000,
            "getTemporalGovCalldata: Timelock publish message calldata max size of 10kb exceeded"
        );
    }

    /// @notice return arrays of all items in the proposal that the
    /// temporal governor will receive
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues(
        Addresses addresses
    ) public view returns (address[] memory, uint256[] memory, bytes[] memory) {
        address temporalGovernor;
        if (addresses.isAddressSet("TEMPORAL_GOVERNOR")) {
            temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        } else {
            temporalGovernor = addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                sendingChainIdToReceivingChainId[block.chainid]
            );
        }
        return
            getTargetsPayloadsValues(
                addresses.getAddress("WORMHOLE_CORE"),
                temporalGovernor
            );
    }

    /// @notice return arrays of all items in the proposal that the
    /// temporal governor will receive
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues(
        address wormholeCore,
        address temporalGovernor
    ) public view returns (address[] memory, uint256[] memory, bytes[] memory) {
        /// target cannot be address 0 as that call will fail
        /// value can be 0
        /// arguments can be 0 as long as eth is sent

        uint256 proposalLength = moonbeamActions.length;

        if (baseActions.length != 0) {
            proposalLength += 1;
        }

        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            require(
                moonbeamActions[i].target != address(0),
                "Invalid target for governance"
            );

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
        }

        /// only get temporal governor calldata if there are actions to execute on base
        if (baseActions.length != 0) {
            /// fill out final piece of proposal which is the call
            /// to publishMessage on the temporal governor
            targets[moonbeamActions.length] = wormholeCore;
            values[moonbeamActions.length] = 0;
            payloads[moonbeamActions.length] = getTemporalGovCalldata(
                temporalGovernor
            );
        }

        return (targets, values, payloads);
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// ----------------- Helper Functions ------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    /// @notice set the fork IDs for base and moonbeam
    function setForkIds(uint256 _baseForkId, uint256 _moonbeamForkId) external {
        require(
            _baseForkId != _moonbeamForkId,
            "setForkIds: fork IDs cannot be the same"
        );

        baseForkId = _baseForkId;
        moonbeamForkId = _moonbeamForkId;
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// --------------------- Printing ----------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    function printGovernorCalldata(Addresses addresses) public view {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues(addresses);

        string[] memory signatures = new string[](targets.length);

        console.log(
            "------------------ Proposal Targets, Values, Payloads ------------------"
        );
        for (uint256 i = 0; i < signatures.length; i++) {
            signatures[i] = "";
            console.log(
                "target: %s\nvalue: %d\npayload\n",
                targets[i],
                values[i]
            );
            console.logBytes(payloads[i]);
        }

        bytes memory payloadArtemis = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            targets,
            values,
            signatures,
            payloads,
            string(PROPOSAL_DESCRIPTION)
        );

        console.log("Governor artemis proposal calldata");
        console.logBytes(payloadArtemis);

        bytes memory payloadMultichainGovernor = abi.encodeWithSignature(
            "propose(address[],uint256[],bytes[],string)",
            targets,
            values,
            payloads,
            string(PROPOSAL_DESCRIPTION)
        );

        console.log("Governor multichain proposal calldata");
        console.logBytes(payloadMultichainGovernor);
    }

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
            bool[] memory isMoonbeam,
            string[] memory descriptions
        ) = getProposalActionSteps();

        for (uint256 i = 0; i < targets.length; i++) {
            console.log("%d). %s", i + 1, descriptions[i]);
            console.log(
                "target: %s\nvalue: %d\npayload\n%s",
                targets[i],
                values[i],
                isMoonbeam[i]
                    ? "Proposal type: Moonbeam\n"
                    : "Proposal type: Base\n"
            );
            emit log_bytes(calldatas[i]);

            console.log("\n");
        }
    }

    /// @notice Getter function for `GovernorBravoDelegate.propose()` calldata
    function getProposeCalldata(
        address wormoholeCore,
        address temporalGovernor
    ) public view returns (bytes memory proposeCalldata) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = getTargetsPayloadsValues(wormoholeCore, temporalGovernor);

        string[] memory signatures = new string[](targets.length);

        proposeCalldata = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            targets,
            values,
            signatures,
            calldatas,
            string(PROPOSAL_DESCRIPTION)
        );
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// -------------------- OVERRIDES ----------------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------

    /// @notice print out the proposal action steps and which chains they were run on
    function printCalldata(Addresses addresses) public override {
        printProposalActionSteps();
        printGovernorCalldata(addresses);
    }

    function deploy(Addresses, address) public virtual override {}

    function afterDeploy(Addresses, address) public virtual override {}

    function afterDeploySetup(Addresses) public virtual override {}

    function build(Addresses) public virtual override {}

    function teardown(Addresses, address) public pure virtual override {}

    function run(Addresses, address) public virtual override {}

    /// @notice Simulate governance proposal from artemis governor contract
    /// @param wormholeCore address of the wormhole core contract
    /// @param governorAddress address of the Governor Bravo Delegator contract
    /// @param governanceToken address of the governance token of the system
    /// @param proposerAddress address of the proposer
    function _runMoonbeamArtemisGovernor(
        address wormholeCore,
        address governorAddress,
        address governanceToken,
        address proposerAddress
    ) internal {
        _verifyActionsPreRunHybrid(moonbeamActions);

        MoonwellArtemisGovernor governor = MoonwellArtemisGovernor(
            governorAddress
        );

        {
            // Ensure proposer has meets minimum proposal threshold and quorum votes to pass the proposal
            uint256 quorumVotes = governor.quorumVotes();
            uint256 proposalThreshold = governor.proposalThreshold();
            uint256 votingPower = quorumVotes > proposalThreshold
                ? quorumVotes
                : proposalThreshold;

            deal(governanceToken, proposerAddress, votingPower);
            // Delegate proposer's votes to itself
            vm.prank(proposerAddress);
            Well(governanceToken).delegate(proposerAddress);
            vm.roll(block.number + 1);
        }

        bytes memory proposeCalldata = getProposeCalldata(
            wormholeCore,
            governorAddress
        );

        // Register the proposal
        bytes memory data;
        {
            // Execute the proposal
            uint256 gasStart = gasleft();
            vm.prank(proposerAddress);
            data = address(payable(governorAddress)).functionCall(
                proposeCalldata
            );

            console.log("Propose Gas Metering", gasStart - gasleft());
        }
        uint256 proposalId = abi.decode(data, (uint256));

        // Check proposal is in Pending state
        require(
            governor.state(proposalId) ==
                MoonwellArtemisGovernor.ProposalState.Pending
        );

        // Roll to Active state (voting period)
        vm.roll(block.number + governor.votingDelay() + 1);
        vm.warp(block.timestamp + governor.votingDelay() + 1);
        require(
            governor.state(proposalId) ==
                MoonwellArtemisGovernor.ProposalState.Active
        );

        // Vote YES
        vm.prank(proposerAddress);
        governor.castVote(proposalId, 0);

        // Roll to allow proposal state transitions
        vm.roll(block.number + governor.votingPeriod());
        vm.warp(block.timestamp + governor.votingPeriod());
        require(
            governor.state(proposalId) ==
                MoonwellArtemisGovernor.ProposalState.Succeeded
        );

        // Queue the proposal
        governor.queue(proposalId);
        require(
            governor.state(proposalId) ==
                MoonwellArtemisGovernor.ProposalState.Queued
        );

        // Warp to allow proposal execution on timelock
        Timelock timelock = Timelock(address(governor.timelock()));
        vm.warp(block.timestamp + timelock.delay());

        {
            // Execute the proposal
            uint256 gasStart = gasleft();
            governor.execute(proposalId);

            console.log("Execution Gas Metering", gasStart - gasleft());
        }

        require(
            governor.state(proposalId) ==
                MoonwellArtemisGovernor.ProposalState.Executed,
            "Proposal state not executed"
        );

        _verifyMTokensPostRun();

        delete createdMTokens;
        comptroller = address(0);
    }

    /// runs the proposal on moonbeam, verifying the actions through the hook
    /// @param addresses the addresses contract
    /// @param caller the proposer address
    function _runMoonbeamMultichainGovernor(
        Addresses addresses,
        address caller
    ) internal {
        _verifyActionsPreRunHybrid(moonbeamActions);

        address governanceToken = addresses.getAddress("WELL");
        address governorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        MultichainGovernor governor = MultichainGovernor(governorAddress);

        {
            // Ensure proposer has meets minimum proposal threshold and quorum votes to pass the proposal
            uint256 quorumVotes = governor.quorum();
            uint256 proposalThreshold = governor.proposalThreshold();
            uint256 votingPower = quorumVotes > proposalThreshold
                ? quorumVotes
                : proposalThreshold;
            deal(governanceToken, caller, votingPower);

            // Delegate proposer's votes to itself
            vm.prank(caller);
            Well(governanceToken).delegate(caller);
            vm.roll(block.number + 1);
        }

        bytes memory data;
        {
            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory payloads
            ) = getTargetsPayloadsValues(addresses);

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

            console.log("Propose Gas Metering", gasStart - gasleft());
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
            // Execute the proposal
            uint256 gasStart = gasleft();
            governor.execute(proposalId);

            console.log("Execution Gas Metering", gasStart - gasleft());
        }

        require(
            governor.state(proposalId) ==
                IMultichainGovernor.ProposalState.Executed,
            "Proposal state not executed"
        );

        _verifyMTokensPostRun();

        delete createdMTokens;
        comptroller = address(0);
    }

    /// runs the proposal actions on base, verifying the actions through the hook
    /// @param temporalGovernorAddress the temporal governor contract address
    function _runBase(address temporalGovernorAddress) internal {
        _verifyActionsPreRunHybrid(baseActions);

        vm.startPrank(temporalGovernorAddress);

        for (uint256 i = 0; i < baseActions.length; i++) {
            (bool success, ) = baseActions[i].target.call{
                value: baseActions[i].value
            }(baseActions[i].data);

            require(
                success,
                string(
                    abi.encodePacked(
                        "base action failed to address ",
                        baseActions[i].target.toHexString()
                    )
                )
            );
        }

        vm.stopPrank();

        _verifyMTokensPostRun();

        delete createdMTokens;
        comptroller = address(0);
    }
}

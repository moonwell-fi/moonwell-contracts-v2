pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IHybridProposal} from "@proposals/proposalTypes/IHybridProposal.sol";
import {MarketCreationHook} from "@proposals/hooks/MarketCreationHook.sol";

/// @notice this is a proposal type to be used for proposals that
/// require actions to be taken on both moonbeam and base.
/// This is a bit wonky because we are trying to simulate
/// what happens on two different networks. So we need to have
/// two different proposal types. One for moonbeam and one for base.
/// We also need to have references to both networks in the proposal
/// to switch between forks.
abstract contract HybridProposal is
    IHybridProposal,
    MarketCreationHook,
    Proposal
{
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
            descriptions[i + indexStart] = moonbeamActions[i].description;
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
        /// target cannot be address 0 as that call will fail
        /// value can be 0
        /// arguments can be 0 as long as eth is sent

        uint256 proposalLength = moonbeamActions.length;

        address[] memory targets = new address[](proposalLength + 1);
        uint256[] memory values = new uint256[](proposalLength + 1);
        bytes[] memory payloads = new bytes[](proposalLength + 1);

        for (uint256 i = 0; i < proposalLength; i++) {
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

        /// fill out final piece of proposal which is the call
        /// to publishMessage on the temporal governor
        targets[proposalLength] = addresses.getAddress("TEMPORAL_GOVERNOR");
        values[proposalLength] = 0;
        payloads[proposalLength] = getTemporalGovCalldata(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        return (targets, values, payloads);
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

    /// @notice print out the proposal action steps and which chains they were run on
    function printCalldata(Addresses) public override {
        printProposalActionSteps();
    }

    function run(Addresses, address) public virtual override {
        /// pre-run verify hooks
        _verifyActionsPreRunHybrid(moonbeamActions);

        /// run actions on moonbeam
        // _simulateGovProposal(addresses.getAddress("MULTISIG"));

        /// post-run verify hooks
        _verifyMTokensPostRun();

        /// wipe hook data in Market Creation Hook

        delete createdMTokens;
        comptroller = address(0);

        /// pre-run verify hooks
        _verifyActionsPreRunHybrid(baseActions);

        /// run actions on base
        /// TODO figure this out
        // _simulateTemporalGovernorActions(addresses.getAddress("MULTISIG"));

        /// post-run verify hooks
        _verifyMTokensPostRun();

        /// wipe hook data in Market Creation Hook

        delete createdMTokens;
        comptroller = address(0);
    }
}

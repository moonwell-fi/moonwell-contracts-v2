pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Bytes} from "@utils/Bytes.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {ProposalChecker} from "@proposals/proposalTypes/ProposalChecker.sol";
import {MultisigProposal} from "@proposals/proposalTypes/MultisigProposal.sol";
import {MarketCreationHook} from "@proposals/hooks/MarketCreationHook.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

/// Reuse Multisig Proposal contract for readability and to avoid code duplication
abstract contract CrossChainProposal is
    ChainIds,
    ProposalChecker,
    MultisigProposal,
    MarketCreationHook
{
    using Bytes for bytes;

    uint32 private constant nonce = 0; /// nonce for wormhole, unused by Temporal Governor

    /// instant finality on moonbeam https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint16 public constant consistencyLevel = 200;

    /// @notice hex encoded description of the proposal
    bytes public PROPOSAL_DESCRIPTION;

    /// @notice set the governance proposal's description
    function _setProposalDescription(
        bytes memory newProposalDescription
    ) internal {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

    /// @notice push a CrossChain proposal action
    function _pushCrossChainAction(
        uint256 value,
        address target,
        bytes memory data,
        string memory description
    ) internal {
        require(value == 0, "Cross chain proposal cannot have value");
        _pushMultisigAction(value, target, data, description);
    }

    /// @notice push a CrossChain proposal action with a value of 0
    function _pushCrossChainAction(
        address target,
        bytes memory data,
        string memory description
    ) internal {
        _pushCrossChainAction(0, target, data, description);
    }

    /// @notice simulate cross chain proposal
    /// @param temporalGovAddress address of the cross chain governor executing the calls
    /// run pre and post proposal hooks to ensure that mToken markets created by the
    /// proposal are valid and mint at least 1 wei worth of mTokens to address 0
    function _simulateCrossChainActions(
        Addresses addresses,
        address temporalGovAddress
    ) internal {
        {
            (address[] memory targets, , ) = getTargetsPayloadsValues(
                addresses
            );
            checkBaseActions(targets, addresses);
            checkMoonbeamBaseActions(
                addresses,
                actions,
                new ProposalAction[](0)
            );

            bytes memory proposalCalldata = getMultichainGovernorCalldata(
                temporalGovAddress,
                addresses.getAddress(
                    block.chainid == baseChainId ||
                        block.chainid == moonBeamChainId
                        ? "WORMHOLE_CORE_MOONBEAM"
                        : "WORMHOLE_CORE_MOONBASE",
                    block.chainid == baseChainId ||
                        block.chainid == moonBeamChainId
                        ? moonBeamChainId
                        : moonBaseChainId
                )
            );

            (address[] memory baseTargets, , , ) = abi.decode(
                proposalCalldata.slice(4, proposalCalldata.length - 4),
                (address[], uint256[], bytes[], string)
            );

            address expectedAddress = block.chainid == baseChainId ||
                block.chainid == moonBeamChainId
                ? addresses.getAddress(
                    "WORMHOLE_CORE_MOONBEAM",
                    moonBeamChainId
                )
                : addresses.getAddress(
                    "WORMHOLE_CORE_MOONBASE",
                    moonBaseChainId
                );
            require(baseTargets.length == 1);
            require(
                baseTargets[0] == expectedAddress,
                "target incorrect, not wormhole core"
            );
        }

        _verifyActionsPreRun(actions);
        _simulateMultisigActions(temporalGovAddress);
        _verifyMTokensPostRun();
    }

    /// @notice calls getTargetsPayloadsValues()
    function getTargetsPayloadsValues(
        Addresses /// shhh
    )
        public
        view
        override
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        return getTargetsPayloadsValues();
    }

    /// @notice return arrays of all items in the proposal that the
    /// temporal governor will receive
    /// all items are in the same order as the proposal
    /// the length of each array is the same as the number of actions in the proposal
    function getTargetsPayloadsValues()
        public
        view
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {
        /// target cannot be address 0 as that call will fail
        /// value can be 0
        /// arguments can be 0 as long as eth is sent

        uint256 proposalLength = actions.length;

        address[] memory targets = new address[](proposalLength);
        uint256[] memory values = new uint256[](proposalLength);
        bytes[] memory payloads = new bytes[](proposalLength);

        for (uint256 i = 0; i < proposalLength; i++) {
            require(
                actions[i].target != address(0),
                "Invalid target for governance"
            );

            /// if there is no calldata and no eth, the action is not valid
            require(
                (actions[i].data.length == 0 && actions[i].value > 0) ||
                    actions[i].data.length > 0,
                "Invalid arguments for governance"
            );

            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            payloads[i] = actions[i].data;
        }

        return (targets, values, payloads);
    }

    /// @notice get the calldata that the timelock on moonbeam will execute in order to publish the cross chain proposal
    /// @param temporalGovernor address of the cross chain governor executing the calls
    function getTemporalGovCalldata(
        address temporalGovernor
    ) public view returns (bytes memory timelockCalldata) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues();

        require(
            temporalGovernor != address(0),
            "getTemporalGovCalldata: Invalid temporal governor"
        );

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

    /// @notice get the calldata for the Artemis Governor to propose the cross chain proposal on Moonbeam
    /// @param temporalGovernor address of the cross chain governor executing the calls
    /// @param wormholeCore address of the wormhole core contract
    function getMultichainGovernorCalldata(
        address temporalGovernor,
        address wormholeCore
    ) public view returns (bytes memory) {
        require(
            temporalGovernor != address(0),
            "getMultichainGovernorCalldata: Invalid temporal governor"
        );
        require(
            wormholeCore != address(0),
            "getMultichainGovernorCalldata: Invalid womrholecore"
        );

        bytes memory temporalGovCalldata = getTemporalGovCalldata(
            temporalGovernor
        );

        return
            getMultichainGovernorCalldata(
                temporalGovernor,
                wormholeCore,
                temporalGovCalldata
            );
    }

    function getMultichainGovernorCalldata(
        address temporalGovernor,
        address wormholeCore,
        bytes memory temporalGovCalldata
    ) public view returns (bytes memory) {
        require(
            temporalGovernor != address(0),
            "getMultichainGovernorCalldata: Invalid temporal governor"
        );
        require(
            wormholeCore != address(0),
            "getMultichainGovernorCalldata: Invalid Wormholecore"
        );

        address[] memory targets = new address[](1);
        targets[0] = wormholeCore;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = temporalGovCalldata;

        bytes memory multichainPayload = abi.encodeWithSignature(
            "propose(address[],uint256[],bytes[],string)",
            targets,
            values,
            payloads,
            string(PROPOSAL_DESCRIPTION)
        );

        return multichainPayload;
    }

    /// @notice search for a on-chain proposal that matches the proposal calldata
    /// @param addresses the addresses contract
    /// @param governor the governor address
    // /// @return proposalId the proposal id, 0 if no proposal is found
    function getProposalId(
        Addresses addresses,
        address governor
    ) public override returns (uint256 proposalId) {
        // CrossChainProposal is only used for proposals that the primery type
        // is Base, this is a temporary solution until we get rid of CrossChainProposal
        vm.selectFork(forkIds[1]);

        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        uint256 proposalCount = MultichainGovernor(governor).proposalCount();

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

            bytes memory proposalCalldata = getMultichainGovernorCalldata(
                temporalGovernor,
                addresses.getAddress(
                    block.chainid == moonBeamChainId
                        ? "WORMHOLE_CORE_MOONBEAM"
                        : "WORMHOLE_CORE_MOONBASE",
                    block.chainid == moonBeamChainId
                        ? moonBeamChainId
                        : moonBaseChainId
                )
            );

            if (keccak256(proposalCalldata) == keccak256(onchainCalldata)) {
                proposalId = proposalCount;
                break;
            }

            proposalCount--;
        }

        vm.selectFork(forkIds[0]);
    }

    /// @notice print the actions that will be executed by the proposal
    /// @param temporalGovernor address of the cross chain governor executing the calls
    /// @param wormholeCore address of the wormhole core contract
    function printActions(
        address temporalGovernor,
        address wormholeCore
    ) public {
        /// if wormhole core is address 0, catch in this function call
        /// if temporal governor is address 0, catch in this function call
        bytes memory multichainPayload = getMultichainGovernorCalldata(
            temporalGovernor,
            wormholeCore
        );

        console.log("Multichain governor queue governance calldata");
        emit log_bytes(multichainPayload);
    }

    function printProposalActionSteps() public override {
        console.log(
            "\n\nProposal Description:\n\n%s",
            string(PROPOSAL_DESCRIPTION)
        );

        console.log(
            "\n\n------------------ Proposal Actions ------------------"
        );

        for (uint256 i = 0; i < actions.length; i++) {
            console.log("%d). %s", i + 1, actions[i].description);
            console.log(
                "target: %s\nvalue: %d\npayload",
                actions[i].target,
                actions[i].value
            );
            emit log_bytes(actions[i].data);

            console.log("\n");
        }
    }

    function printCalldata(Addresses addresses) public override {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            /// if moonbeam or base use wormhole core on moonbeam, else use moonbase
            block.chainid == moonBeamChainId || block.chainid == baseChainId
                ? addresses.getAddress(
                    "WORMHOLE_CORE_MOONBEAM",
                    moonBeamChainId
                )
                : addresses.getAddress(
                    "WORMHOLE_CORE_MOONBASE",
                    moonBaseChainId
                )
        );
    }

    function run(Addresses addresses, address) public virtual override {
        _simulateCrossChainActions(
            addresses,
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
    }
}

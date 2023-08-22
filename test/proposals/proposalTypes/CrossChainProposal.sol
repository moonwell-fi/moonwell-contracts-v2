pragma solidity 0.8.19;

import {MarketCreationHook} from "@test/proposals/hooks/MarketCreationHook.sol";
import {MultisigProposal} from "@test/proposals/proposalTypes/MultisigProposal.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";

import "@forge-std/Test.sol";

import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

/// Reuse Multisig Proposal contract for readability and to avoid code duplication
abstract contract CrossChainProposal is MultisigProposal, MarketCreationHook {
    uint32 public nonce; /// nonce for wormhole

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

    /// @notice set the nonce for the cross chain proposal
    function _setNonce(uint32 _nonce) internal {
        nonce = _nonce;
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
    function _simulateCrossChainActions(address temporalGovAddress) internal {
        _verifyActionsPreRun(actions);
        _simulateMultisigActions(temporalGovAddress);
        _verifyMTokensPostRun();
    }

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

            /// if there are no args and no eth, the action is not valid
            require(
                (actions[i].arguments.length == 0 && actions[i].value > 0) ||
                    actions[i].arguments.length > 0,
                "Invalid arguments for governance"
            );

            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            payloads[i] = actions[i].arguments;
        }

        return (targets, values, payloads);
    }

    function getTemporalGovCalldata(
        address temporalGovernor
    ) public view returns (bytes memory) {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory payloads
        ) = getTargetsPayloadsValues();

        /// TODO verify calldata size is under wormhole max message size limit
        return
            abi.encodeWithSignature(
                "publishMessage(uint32,bytes,uint8)",
                nonce,
                abi.encode(temporalGovernor, targets, values, payloads),
                consistencyLevel
            );
    }

    function getArtemisGovernorCalldata(
        address temporalGovernor,
        address wormholeCore
    ) public view returns (bytes memory) {
        bytes memory temporalGovCalldata = getTemporalGovCalldata(
            temporalGovernor
        );

        address[] memory targets = new address[](1);
        targets[0] = wormholeCore;

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory payloads = new bytes[](1);
        payloads[0] = temporalGovCalldata;

        string[] memory signatures = new string[](1);
        signatures[0] = "";

        bytes memory artemisPayload = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            targets,
            values,
            signatures,
            payloads,
            string(PROPOSAL_DESCRIPTION)
        );

        return artemisPayload;
    }

    function printActions(
        address temporalGovernor,
        address wormholeCore
    ) public {
        bytes memory temporalGovCalldata = getTemporalGovCalldata(
            temporalGovernor
        );

        console.log("temporal governance calldata");
        emit log_bytes(temporalGovCalldata);

        bytes memory wormholeTemporalGovPayload = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            nonce,
            temporalGovCalldata,
            consistencyLevel
        );

        console.log("wormhole publish governance calldata");
        emit log_bytes(wormholeTemporalGovPayload);

        bytes memory artemisPayload = getArtemisGovernorCalldata(
            temporalGovernor,
            wormholeCore
        );

        console.log("artemis governor queue governance calldata");
        emit log_bytes(artemisPayload);
    }

    function printProposalActionSteps() public {
        console.log(
            "\n\nProposal Description:\n\n%s",
            string(PROPOSAL_DESCRIPTION)
        );

        console.log(
            "\n\n------------------ Proposal Actions ------------------"
        );

        for (uint256 i = 0; i < actions.length; i++) {
            console.log("%d). %s", i + 1, actions[i].description);
            console.log("target: %s\npayload", actions[i].target);
            emit log_bytes(actions[i].arguments);

            console.log("\n");
        }
    }
}

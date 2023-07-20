pragma solidity ^0.8.0;

import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import "@forge-std/Test.sol";

import {MoonwellGovernorArtemis} from "@protocol/core/Governance/deprecated/MoonwellArtemisGovernor.sol";

abstract contract CrossChainProposal is Proposal {
    struct CrossChainAction {
        address target;
        uint256 value;
        bytes arguments;
        string description;
    }

    uint32 private nonce;

    /// instant finality on moonbeam https://book.wormhole.com/wormhole/3_coreLayerContracts.html?highlight=consiste#consistency-levels
    uint16 public constant consistencyLevel = 200;

    CrossChainAction[] public actions;

    /// @notice set the nonce for the cross chain proposal
    function _setNonce(uint32 _nonce) internal {
        nonce = _nonce;
    }

    /// @notice push an action to the CrossChain proposal
    function _pushCrossChainAction(
        uint256 value,
        address target,
        bytes memory data,
        string memory description
    ) internal {
        actions.push(
            CrossChainAction({
                value: value,
                target: target,
                arguments: data,
                description: description
            })
        );
    }

    /// @notice push an action to the CrossChain proposal with a value of 0
    function _pushCrossChainAction(
        address target,
        bytes memory data,
        string memory description
    ) internal {
        _pushCrossChainAction(0, target, data, description);
    }

    /// @notice simulate cross chain proposal
    /// @param temporalGovAddress address of the cross chain governor executing the calls
    function _simulateCrossChainActions(address temporalGovAddress) internal {
        vm.startPrank(temporalGovAddress);

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = actions[i].target.call{
                value: actions[i].value
            }(actions[i].arguments);

            require(success, string(result));
        }

        vm.stopPrank();

        // printActions(temporalGovAddress);
    }

    function printActions(
        address intendedRecipient,
        address wormholeCore
    ) public {
        bytes memory temporalGovCalldata;
        /// target cannot be address 0 as that call will fail
        /// value can be 0
        /// arguments can be 0 as long as eth is sent
        {
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
                    (actions[i].arguments.length == 0 &&
                        actions[i].value > 0) ||
                        actions[i].arguments.length > 0,
                    "Invalid arguments for governance"
                );

                targets[i] = actions[i].target;
                values[i] = actions[i].value;
                payloads[i] = actions[i].arguments;
            }

            temporalGovCalldata = abi.encode(
                intendedRecipient,
                targets,
                values,
                payloads
            );
        }
        {
            address[] memory targets = new address[](1);
            targets[0] = wormholeCore;

            uint256[] memory values = new uint256[](1);
            values[0] = 0;

            bytes[] memory payloads = new bytes[](1);
            payloads[0] = temporalGovCalldata;

            string[] memory signatures = new string[](1);
            signatures[0] = "publishMessage(uint32,bytes,uint8)";

            bytes memory artemisPayload = abi.encode(
                MoonwellGovernorArtemis.propose.selector,
                targets,
                values,
                signatures,
                payloads,
                "Cross chain governance proposal"
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

            console.log("artemis governor queue governance calldata");
            emit log_bytes(artemisPayload);
        }
    }
}

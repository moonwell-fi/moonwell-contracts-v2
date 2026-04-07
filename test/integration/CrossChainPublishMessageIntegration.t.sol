// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20Votes} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";

import "@forge-std/Test.sol";

import {ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {String} from "@utils/String.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from "@protocol/interfaces/IArtemisGovernor.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata
contract CrossChainPublishMessageTest is Test, PostProposalCheck {
    using String for string;
    using ChainIds for uint256;

    IWormhole public wormhole;
    ERC20Votes public well;

    address public constant voter = address(100_000_000);

    function setUp() public override {
        super.setUp();

        vm.selectFork(MOONBEAM_FORK_ID);

        wormhole = IWormhole(addresses.getAddress("WORMHOLE_CORE"));
        vm.makePersistent(address(wormhole));

        well = ERC20Votes(addresses.getAddress("GOVTOKEN"));
        vm.makePersistent(address(well));
    }

    function testMintSelf() public {
        uint256 transferAmount = well.balanceOf(
            0x933fCDf708481c57E9FD82f6BAA084f42e98B60e
        );
        vm.prank(0x933fCDf708481c57E9FD82f6BAA084f42e98B60e);
        well.transfer(voter, transferAmount);

        vm.prank(voter);
        well.delegate(voter); /// delegate to self

        vm.roll(block.number + 1000);
        vm.warp(block.timestamp + 1000);
    }

    function testQueueAndPublishMessageRawBytes() public {
        if (proposals.length == 0) {
            /// if no proposals to execute, return
            return;
        }

        for (uint256 i = 0; i < proposals.length; i++) {
            HybridProposal proposal = HybridProposal(address(proposals[i]));

            //  only run tests against a base proposal
            if (uint256(proposal.primaryForkId()) == MOONBEAM_FORK_ID) {
                return;
            }

            addresses.removeAllRestrictions();
            // Run beforeSimulationHook to set up pre-conditions
            // (e.g. multisig approvals, mock relayers for cross-chain bridging)
            proposal.beforeSimulationHook(addresses);
            // At this point the primaryForkId should not be moonbeam
            vm.selectFork(uint256(proposal.primaryForkId()));
            proposal.build(addresses);

            /// this returns the moonbeam wormhole core address as
            /// block.chainid is base/base sepolia optimism/optimism sepolia
            address wormholeCore = addresses.getAddress(
                "WORMHOLE_CORE",
                block.chainid.toMoonbeamChainId()
            );

            bytes memory multichainGovernorQueuePayload = proposal.getCalldata(
                addresses
            );

            console.log("MultichainGovernor queue governance calldata");
            emit log_bytes(multichainGovernorQueuePayload);

            vm.selectFork(MOONBEAM_FORK_ID);

            testMintSelf();
            {
                uint256 cost = governor.bridgeCostAll();
                vm.deal(voter, cost);
                vm.prank(voter);
                (bool success, ) = address(governor).call{value: cost}(
                    multichainGovernorQueuePayload
                );

                require(success, "proposing gov proposal on moonbeam failed");
            }

            /// -----------------------------------------------------------
            /// -----------------------------------------------------------
            /// ---------------- ADDRESS SANITY CHECKS --------------------
            /// -----------------------------------------------------------
            /// -----------------------------------------------------------

            require(
                wormholeCore != address(0),
                "invalid temporal governor address"
            );

            uint256 proposalId = governor.proposalCount();

            vm.prank(voter);
            governor.castVote(proposalId, 0); /// VOTE YES

            vm.warp(
                governor.votingPeriod() +
                    governor.crossChainVoteCollectionPeriod() +
                    block.timestamp +
                    1
            );

            /// @dev nextSequence removed — was unused and IWormhole.nextSequence
            ///      is not view-compatible with the on-chain Wormhole core

            bytes memory temporalGovExecDataBase;
            if (proposal.getActionsByType(ActionType.Base).length != 0) {
                temporalGovExecDataBase = proposal.getTemporalGovPayloadByChain(
                    addresses,
                    block.chainid.toBaseChainId()
                );
            }

            bytes memory temporalGovExecDataOptimism;
            if (proposal.getActionsByType(ActionType.Optimism).length != 0) {
                temporalGovExecDataOptimism = proposal
                    .getTemporalGovPayloadByChain(
                        addresses,
                        block.chainid.toOptimismChainId()
                    );
            }

            // Calculate total ETH value needed for Moonbeam actions
            uint256 executeValue = 0;
            {
                ProposalAction[] memory moonbeamActions = proposal
                    .getActionsByType(ActionType.Moonbeam);
                for (uint256 k = 0; k < moonbeamActions.length; k++) {
                    executeValue += moonbeamActions[k].value;
                }
            }
            vm.deal(address(this), executeValue);

            vm.recordLogs();
            governor.execute{value: executeValue}(proposalId);
            Vm.Log[] memory logs = vm.getRecordedLogs();

            bytes32 sig = keccak256(
                "LogMessagePublished(address,uint64,uint32,bytes,uint8)"
            );
            if (temporalGovExecDataBase.length != 0) {
                bool seenBase = false;
                for (uint256 k = 0; k < logs.length; k++) {
                    if (
                        logs[k].emitter == wormholeCore &&
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
                    "Missing LogMessagePublished event on Base"
                );
            }

            if (temporalGovExecDataOptimism.length != 0) {
                bool seenOptimism = false;
                for (uint256 k = 0; k < logs.length; k++) {
                    if (
                        logs[k].emitter == wormholeCore &&
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
                    "Missing LogMessagePublished event on Optimism"
                );
            }
        }
    }

    function testExecuteTemporalGovMessage() public {
        testQueueAndPublishMessageRawBytes();

        for (uint256 j = 0; j < proposals.length; j++) {
            HybridProposal proposal = HybridProposal(address(proposals[j]));

            // Only run tests against non-moonbeam proposals
            if (uint256(proposal.primaryForkId()) == MOONBEAM_FORK_ID) {
                return;
            }

            // At this point the primaryForkId should not be moonbeam
            vm.selectFork(uint256(proposal.primaryForkId()));
            (
                address[] memory targets, /// contracts to call /// native token amount to send is ignored as temporal gov cannot accept eth
                ,
                bytes[] memory calldatas
            ) = proposal.getTargetsPayloadsValues(addresses);

            vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

            for (uint256 i = 0; i < targets.length; i++) {
                (bool success, bytes memory errorString) = targets[i].call(
                    abi.encodePacked(calldatas[i])
                );
                require(success, string(errorString));
            }

            vm.stopPrank();
        }
    }
}

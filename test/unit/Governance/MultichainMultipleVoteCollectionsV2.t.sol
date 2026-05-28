pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTestV2} from "@test/helper/MultichainBaseTestV2.t.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {IMultichainGovernorV2, MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

contract MultichainMultipleVoteCollectionsUnitTestV2 is MultichainBaseTestV2 {
    event CrossChainVoteCollected(
        uint256 proposalId,
        uint16 sourceChain,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes
    );

    function testSetup() public view {
        assertEq(
            votingPowerAggregator.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );
        assertEq(
            voteCollection.getVotes(address(this), block.timestamp - 1),
            4_000_000_000 * 1e18,
            "incorrect vote amount"
        );

        // Vote collection has its own VotingPowerAggregator, different from governor's
        assertFalse(
            address(voteCollection.votingPower()) ==
                address(votingPowerAggregator),
            "vote collection should have its own voting power aggregator"
        );
        assertTrue(
            address(voteCollection.votingPower()) != address(0),
            "vote collection voting power aggregator should be set"
        );

        assertEq(
            address(governor.wormhole()),
            address(wormholeRelayerAdapter),
            "incorrect wormhole"
        );
        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "governor not whitelisted to send messages in"
        );
        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection)
            ),
            "voteCollection not whitelisted to send messages in"
        );

        assertTrue(governor.getAllTargetChainsLength() > 0, "no targets");

        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains length"
        );

        assertEq(voteCollection.owner(), address(this), "incorrect owner");
    }

    function testEmitToMultipleVoteCollections()
        public
        returns (address proxyVoteCollection2)
    {
        (proxyVoteCollection2, ) = deployVoteCollectionV2(
            address(0), // create new VotingPowerAggregator
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this)
        );
        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        uint16 chainId = 2;
        _trustedSenders[0].chainId = chainId;
        _trustedSenders[0].addr = address(proxyVoteCollection2);

        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory descriptionUri = "ipfs://QmProposalMIPM00UpdateProposalThreshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            BASE_WORMHOLE_CHAIN_ID,
            bridgeCost / 2,
            address(voteCollection),
            payload
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            chainId,
            bridgeCost / 2,
            proxyVoteCollection2,
            payload
        );

        vm.recordLogs();
        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // finalize
        );

        _deliverBridgeOutEvents(address(governor));

        {
            // vote collections should have the proposal
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
                .proposalInformation(1);
            assertGt(voteSnapshotTimestamp, 0, "proposal id incorrect");
        }

        {
            MultichainVoteCollectionV2 voteCollection2 = MultichainVoteCollectionV2(
                    proxyVoteCollection2
                );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection2
                .proposalInformation(1);

            assertGt(voteSnapshotTimestamp, 1, "proposal id incorrect");
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
    }

    function testEmitToMultipleVoteCollectionsSomeFails() public {
        (address proxyVoteCollection2, ) = deployVoteCollectionV2(
            address(0), // create new VotingPowerAggregator
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this)
        );

        (address proxyVoteCollection3, ) = deployVoteCollectionV2(
            address(0), // create new VotingPowerAggregator
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this)
        );

        (address proxyVoteCollection4, ) = deployVoteCollectionV2(
            address(0), // create new VotingPowerAggregator
            address(xwell),
            address(stkWellBase),
            address(governor),
            address(wormholeRelayerAdapter),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            proxyAdmin,
            address(this)
        );

        WormholeTrustedSender.TrustedSender[]
            memory _trustedSenders = new WormholeTrustedSender.TrustedSender[](
                3
            );

        _trustedSenders[0].chainId = 2;
        _trustedSenders[0].addr = address(proxyVoteCollection2);

        _trustedSenders[1].chainId = 3;
        _trustedSenders[1].addr = address(proxyVoteCollection3);

        _trustedSenders[2].chainId = 4;
        _trustedSenders[2].addr = address(proxyVoteCollection4);

        vm.prank(address(governor));
        governor.addExternalChainConfigs(_trustedSenders);

        uint16[] memory shouldRevertAt = new uint16[](2);
        shouldRevertAt[0] = 2;
        shouldRevertAt[1] = 4;

        wormholeRelayerAdapter.setShouldRevertAtChain(shouldRevertAt, true);

        address proposer = address(1);

        // NOTE: well and distributor removed as voting sources per governance changes
        _delegateVoteAmountForUser(
            address(xwell),
            proposer,
            governor.proposalThreshold()
        );

        vm.warp(block.timestamp + 1);

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(proposer, bridgeCost);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory descriptionUri = "ipfs://QmProposalMIPM00UpdateProposalThreshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 startTimestamp = block.timestamp;
        uint256 endTimestamp = startTimestamp + governor.votingPeriod();
        bytes memory payload = abi.encode(
            1,
            startTimestamp - 1,
            startTimestamp,
            endTimestamp,
            endTimestamp + governor.crossChainVoteCollectionPeriod()
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(
            BASE_WORMHOLE_CHAIN_ID,
            bridgeCost / 4,
            address(voteCollection),
            payload
        );

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(2, payload, bridgeCost / 4);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutSuccess(3, bridgeCost / 4, proxyVoteCollection3, payload);

        vm.expectEmit(true, true, true, true, address(governor));
        emit BridgeOutFailed(4, payload, bridgeCost / 4);

        vm.recordLogs();
        vm.prank(proposer);
        governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            descriptionUri,
            true // finalize
        );

        _deliverBridgeOutEvents(address(governor));

        {
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection
                .proposalInformation(1);
            assertGt(voteSnapshotTimestamp, 0, "proposal doesn't exist");
        }

        {
            MultichainVoteCollectionV2 voteCollection2 = MultichainVoteCollectionV2(
                    proxyVoteCollection2
                );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection2
                .proposalInformation(1);

            assertEq(voteSnapshotTimestamp, 0, "proposal exist");
        }

        {
            MultichainVoteCollectionV2 voteCollection3 = MultichainVoteCollectionV2(
                    proxyVoteCollection3
                );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection3
                .proposalInformation(1);

            assertGt(voteSnapshotTimestamp, 0, "proposal doesn't exist");
        }

        {
            MultichainVoteCollectionV2 voteCollection4 = MultichainVoteCollectionV2(
                    proxyVoteCollection4
                );
            (uint256 voteSnapshotTimestamp, , , , , , , ) = voteCollection4
                .proposalInformation(1);

            assertEq(voteSnapshotTimestamp, 0, "proposal exist");
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
        assertEq(proxyVoteCollection3.balance, 0, "balance should be zero");
        assertEq(proxyVoteCollection4.balance, 0, "balance should be zero");
    }

    function testCollectVotesFromMultipleVoteCollections() public {
        address proxyVoteCollection2 = testEmitToMultipleVoteCollections();
        uint256 proposalId = 1;

        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        MultichainVoteCollectionV2 voteCollection2 = MultichainVoteCollectionV2(
            proxyVoteCollection2
        );
        uint256 voteAmount = 4_000_000_000 * 1e18;

        {
            // votes before

            (
                uint256 totalVotesBefore,
                uint256 votesForBefore,
                uint256 votesAgainstBefore,
                uint256 votesAbstainBefore
            ) = voteCollection.proposalVotes(proposalId);

            // cast votes for both collections
            voteCollection.castVote(proposalId, Constants.VOTE_VALUE_NO);

            // votes after cast
            (
                uint256 totalVotes,
                uint256 votesFor,
                uint256 votesAgainst,
                uint256 votesAbstain
            ) = voteCollection.proposalVotes(proposalId);

            assertEq(votesAgainst, voteAmount, "votes against incorrect");
            assertEq(
                votesAgainst - votesAgainstBefore,
                voteAmount,
                "votes against incorrect"
            );
            assertEq(votesFor, votesForBefore, "votes for incorrect");
            assertEq(
                votesAbstain,
                votesAbstainBefore,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes,
                totalVotesBefore + voteAmount,
                "total votes incorrect"
            );
        }

        {
            (
                uint256 totalVotesBefore2,
                uint256 votesForBefore2,
                uint256 votesAgainstBefore2,
                uint256 votesAbstainBefore2
            ) = voteCollection2.proposalVotes(1);

            voteCollection2.castVote(1, Constants.VOTE_VALUE_YES);

            (
                uint256 totalVotes2,
                uint256 votesFor2,
                uint256 votesAgainst2,
                uint256 votesAbstain2
            ) = voteCollection2.proposalVotes(1);

            assertEq(votesFor2, voteAmount, "votes for incorrect");
            assertEq(
                votesFor2 - votesForBefore2,
                voteAmount,
                "votes for incorrect"
            );
            assertEq(
                votesAgainst2,
                votesAgainstBefore2,
                "votes against incorrect"
            );
            assertEq(
                votesAbstain2,
                votesAbstainBefore2,
                "abstain votes incorrect"
            );
            assertEq(
                totalVotes2,
                totalVotesBefore2 + voteAmount,
                "total votes incorrect"
            );
        }

        // pass to cross chain vote collection period
        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        {
            // total votes on governor
            (
                uint256 totalVotesBefore,
                uint256 votesForBefore,
                uint256 votesAgainstBefore,
                uint256 votesAbstainBefore
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotesBefore, 0, "total votes incorrect");
            assertEq(votesForBefore, 0, "votes for incorrect");
            assertEq(votesAgainstBefore, 0, "votes against incorrect");
            assertEq(votesAbstainBefore, 0, "abstain votes incorrect");

            {
                uint256 bridgeCost = voteCollection.bridgeCost(
                    MOONBEAM_WORMHOLE_CHAIN_ID
                );

                vm.deal(address(this), bridgeCost);

                vm.recordLogs();
                voteCollection.emitVotes{value: bridgeCost}(proposalId);
                _deliverBridgeOutEvents(address(voteCollection));

                {
                    // check chainVoteCollectorVotes
                    (
                        uint256 forVotes,
                        uint256 againstVotes,
                        uint256 abstainVotes
                    ) = governor.chainVoteCollectorVotes(
                            BASE_WORMHOLE_CHAIN_ID,
                            proposalId
                        );

                    assertEq(againstVotes, voteAmount, "chain votes incorrect");
                    assertEq(forVotes, 0, "chain votes incorrect");
                    assertEq(abstainVotes, 0, "chain votes incorrect");
                }

                // check proposal votes after
                (
                    uint256 totalVotes,
                    uint256 votesFor,
                    uint256 votesAgainst,
                    uint256 votesAbstain
                ) = governor.proposalVotes(proposalId);

                assertEq(
                    votesAgainst,
                    voteAmount,
                    "governor votes against incorrect"
                );
                assertEq(
                    votesFor,
                    votesForBefore,
                    "governor votes for incorrect"
                );
                assertEq(
                    votesAbstain,
                    votesAbstainBefore,
                    "governor abstain votes incorrect"
                );
                assertEq(
                    totalVotes,
                    totalVotesBefore + votesAgainst,
                    "governor total votes incorrect"
                );
            }

            {
                uint256 bridgeCost = voteCollection2.bridgeCost(
                    MOONBEAM_WORMHOLE_CHAIN_ID
                );

                vm.deal(address(this), bridgeCost);

                wormholeRelayerAdapter.setSenderChainId(2);

                vm.recordLogs();
                voteCollection2.emitVotes{value: bridgeCost}(proposalId);
                _deliverBridgeOutEvents(address(voteCollection2));

                {
                    // check chainVoteCollectorVotes
                    (
                        uint256 forVotes,
                        uint256 againstVotes,
                        uint256 abstainVotes
                    ) = governor.chainVoteCollectorVotes(2, proposalId);

                    assertEq(againstVotes, 0, "chain votes incorrect");
                    assertEq(forVotes, voteAmount, "chain votes incorrect");
                    assertEq(abstainVotes, 0, "chain votes incorrect");
                }

                // check proposal votes after
                (
                    uint256 totalVotes,
                    uint256 votesFor,
                    uint256 votesAgainst,
                    uint256 votesAbstain
                ) = governor.proposalVotes(1);

                assertEq(
                    votesFor,
                    votesForBefore + voteAmount,
                    "votes for incorrect"
                );
                assertEq(
                    votesAgainst,
                    votesAgainstBefore + voteAmount,
                    "votes against incorrect"
                );
                assertEq(
                    votesAbstain,
                    votesAbstainBefore,
                    "abstain votes incorrect"
                );
                assertEq(
                    totalVotes,
                    totalVotesBefore + voteAmount * 2,
                    "total votes incorrect"
                );
            }
        }

        _assertGovernanceBalance();
        assertEq(proxyVoteCollection2.balance, 0, "balance should be zero");
    }
}

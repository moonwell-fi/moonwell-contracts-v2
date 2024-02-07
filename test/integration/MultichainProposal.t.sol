// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {TestMultichainProposals} from "@protocol/proposals/TestMultichainProposals.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";

import {mipm18a} from "@proposals/mips/mip-m18/mip-m18a.sol";
import {mipm18b} from "@proposals/mips/mip-m18/mip-m18b.sol";
import {mipm18c} from "@proposals/mips/mip-m18/mip-m18c.sol";
import {mipm18d} from "@proposals/mips/mip-m18/mip-m18d.sol";
import {mipm18e} from "@proposals/mips/mip-m18/mip-m18e.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata

/*
if the tests fail, try setting the environment variables as follows:

export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_AFTER_DEPLOY_SETUP=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=true
export DO_VALIDATE=true

*/
contract MultichainProposalTest is
    Test,
    ChainIds,
    CreateCode,
    TestMultichainProposals
{
    MultichainVoteCollection public voteCollection;
    MultichainGovernor public governor;
    IWormhole public wormhole;
    Timelock public timelock;
    Well public well;
    xWELL public xwell;

    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    uint256 public baseForkId = vm.createFork("https://mainnet.base.org");

    uint256 public moonbeamForkId =
        vm.createFork("https://rpc.api.moonbeam.network");

    address public constant voter = address(100_000_000);

    function setUp() public override {
        super.setUp();

        mipm18a proposalA = new mipm18a();
        mipm18b proposalB = new mipm18b();
        mipm18c proposalC = new mipm18c();
        mipm18d proposalD = new mipm18d();
        mipm18e proposalE = new mipm18e();

        address[] memory proposalsArray = new address[](5);
        proposalsArray[0] = address(proposalA);
        proposalsArray[1] = address(proposalB);
        proposalsArray[2] = address(proposalC);
        proposalsArray[3] = address(proposalD);
        proposalsArray[4] = address(proposalE);

        proposalA.setForkIds(baseForkId, moonbeamForkId);
        proposalB.setForkIds(baseForkId, moonbeamForkId);
        proposalC.setForkIds(baseForkId, moonbeamForkId);
        proposalD.setForkIds(baseForkId, moonbeamForkId);
        proposalE.setForkIds(baseForkId, moonbeamForkId);

        /// load proposals up into the TestMultichainProposal contract
        _initialize(proposalsArray);

        vm.selectFork(moonbeamForkId);
        runProposals();

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY", baseChainId)
        );
        wormhole = IWormhole(
            addresses.getAddress("WORMHOLE_CORE", moonBeamChainId)
        );
        well = Well(addresses.getAddress("WELL", moonBeamChainId));
        timelock = Timelock(
            addresses.getAddress("MOONBEAM_TIMELOCK", moonBeamChainId)
        );
        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY", moonBeamChainId)
        );
    }

    function testSetup() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );

        assertEq(
            voteCollection.gasLimit(),
            Constants.MIN_GAS_LIMIT,
            "incorrect gas limit vote collection"
        );
        assertEq(
            address(voteCollection.wormholeRelayer()),
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
            "incorrect wormhole relayer"
        );
        assertEq(
            address(voteCollection.xWell()),
            addresses.getAddress("xWELL_PROXY"),
            "incorrect xWELL contract"
        );
        assertEq(
            address(voteCollection.stkWell()),
            addresses.getAddress("stkWELL_PROXY"),
            "incorrect xWELL contract"
        );
    }

    function testInitializeVoteCollectionFails() public {
        vm.selectFork(baseForkId);
        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        );
        /// test impl and logic contract initialization
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );

        voteCollection = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        voteCollection.initialize(
            address(0),
            address(0),
            address(0),
            address(0),
            uint16(0),
            address(0)
        );
    }

    function testInitializeMultichainGovernorFails() public {
        vm.selectFork(moonbeamForkId);
        /// test impl and logic contract initialization
        MultichainGovernor.InitializeData memory initializeData;
        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                0
            );
        bytes[] memory whitelistedCalldata = new bytes[](0);

        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL")
        );
        vm.expectRevert("Initializable: contract is already initialized");
        governor.initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
    }

    function testRetrieveGasPriceMoonbeamSucceeds() public {
        vm.selectFork(moonbeamForkId);

        uint256 gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testRetrieveGasPriceBaseSucceeds() public {
        vm.selectFork(baseForkId);

        uint256 gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCost(baseWormholeChainId);

        assertTrue(gasCost != 0, "gas cost is 0 bridgeCost");

        gasCost = MultichainVoteCollection(
            addresses.getAddress("VOTE_COLLECTION_PROXY")
        ).bridgeCostAll();

        assertTrue(gasCost != 0, "gas cost is 0 gas cost all");
    }

    function testProposeOnMoonbeamWellSucceeds() public {
        vm.selectFork(moonbeamForkId);
        vm.roll(block.number + 1);

        /// mint whichever is greater, the proposal threshold or the quorum
        uint256 mintAmount = governor.proposalThreshold() > governor.quorum()
            ? governor.proposalThreshold()
            : governor.quorum();

        deal(address(well), address(this), mintAmount);
        well.transfer(address(this), mintAmount);
        well.delegate(address(this));

        vm.roll(block.number + 1);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string
            memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature(
            "updateProposalThreshold(uint256)",
            100_000_000 * 1e18
        );

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        uint256 proposalId = governor.propose{value: bridgeCost}(
            targets,
            values,
            calldatas,
            description
        );

        assertEq(proposalId, 1, "incorrect proposal id");
        assertEq(
            uint256(governor.state(proposalId)),
            0,
            "incorrect proposal state"
        );

        assertTrue(
            governor.userHasProposal(proposalId, address(this)),
            "user has proposal"
        );
        assertTrue(
            governor.proposalValid(proposalId),
            "user does not have proposal"
        );

        {
            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(totalVotes, 0, "incorrect total votes");
            assertEq(forVotes, 0, "incorrect for votes");
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }

        /// vote yes on proposal
        governor.castVote(proposalId, 0);

        {
            (bool hasVoted, uint8 voteValue, uint256 votes) = governor
                .getReceipt(proposalId, address(this));
            assertTrue(hasVoted, "has voted incorrect");
            assertEq(voteValue, 0, "vote value incorrect");
            assertEq(votes, governor.getCurrentVotes(address(this)), "votes");

            (
                uint256 totalVotes,
                uint256 forVotes,
                uint256 againstVotes,
                uint256 abstainVotes
            ) = governor.proposalVotes(proposalId);

            assertEq(
                totalVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect total votes"
            );
            assertEq(
                forVotes,
                governor.getCurrentVotes(address(this)),
                "incorrect for votes"
            );
            assertEq(againstVotes, 0, "incorrect against votes");
            assertEq(abstainVotes, 0, "incorrect abstain votes");
        }
        {
            (
                ,
                ,
                ,
                ,
                uint256 crossChainVoteCollectionEndTimestamp,
                ,
                ,
                ,

            ) = governor.proposalInformation(proposalId);

            vm.warp(crossChainVoteCollectionEndTimestamp - 1);

            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period"
            );

            vm.warp(crossChainVoteCollectionEndTimestamp);
            assertEq(
                uint256(governor.state(proposalId)),
                1,
                "not in xchain vote collection period at end"
            );

            vm.warp(block.timestamp + 1);
            assertEq(
                uint256(governor.state(proposalId)),
                4,
                "not in succeeded at end"
            );
        }

        {
            governor.execute(proposalId);

            assertEq(
                address(governor).balance,
                0,
                "incorrect governor balance"
            );
            assertEq(
                governor.proposalThreshold(),
                100_000_000 * 1e18,
                "incorrect new proposal threshold"
            );
            assertEq(uint256(governor.state(proposalId)), 5, "not in executed");
        }
    }

    function testVotingOnBasexWellSucceeds() public {}

    function testVotingOnBasestkWellSucceeds() public {}

    function testVotingOnBasestkWellPostVotingPeriodFails() public {}

    function testEmittingVotesMultipleTimesVoteCollectionPeriodSucceeds()
        public
    {}

    function testReceiveProposalFromRelayersSucceeds() public {}

    function testReceiveSameProposalFromRelayersTwiceFails() public {}

    function testEmittingVotesPostVoteCollectionPeriodFails() public {}

    /// upgrading contract logic

    function testUpgradeMultichainGovernorThroughGovProposal() public {}

    function testUpgradeMultichainVoteCollection() public {}
}

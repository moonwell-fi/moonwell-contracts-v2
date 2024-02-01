// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {StringUtils} from "@proposals/utils/StringUtils.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";
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
contract MultichainProposalTest is
    Test,
    ChainIds,
    CreateCode,
    TestMultichainProposals
{
    using StringUtils for string;

    MultichainVoteCollection public voteCollection;
    MoonwellArtemisGovernor public governor;
    IWormhole public wormhole;
    Timelock public timelock;
    Well public well;

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

        wormhole = IWormhole(
            addresses.getAddress("WORMHOLE_CORE", moonBeamChainId)
        );
        well = Well(addresses.getAddress("WELL", moonBeamChainId));
        timelock = Timelock(
            addresses.getAddress("MOONBEAM_TIMELOCK", moonBeamChainId)
        );
        governor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR", moonBeamChainId)
        );

        vm.selectFork(moonbeamForkId);
        runProposals();
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

    function testVotingOnBasexWellSucceeds() public {}

    function testVotingOnBasestkWellSucceeds() public {}

    function testVotingOnBasestkWellPostVotingPeriodFails() public {}

    function testEmittingVotesMultipleTimesVoteCollectionPeriodSucceeds()
        public
    {}

    function testReceiveProposalFromRelayersSucceeds() public {}

    function testReceiveSameProposalFromRelayersTwiceFails() public {}

    function testEmittingVotesPostVoteCollectionPeriodFails() public {}
}

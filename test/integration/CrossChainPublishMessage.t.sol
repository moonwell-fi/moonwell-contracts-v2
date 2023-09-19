// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {IWormhole} from "@protocol/Governance/IWormhole.sol";
import {mipb05 as mip} from "@test/proposals/mips/mip-b05/mip-b05.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata
contract CrossChainPublishMessageTest is Test, ChainIds {
    MoonwellArtemisGovernor governor;
    IWormhole wormhole;
    TestProposals proposals;
    Addresses addresses;
    Timelock timelock;
    Well well;
    bytes artemisQueuePayload;

    string public constant BASE_RPC_ENV_NAME = "BASE_RPC_URL";
    string public constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    uint256 public baseForkId =
        vm.createFork(vm.envOr(BASE_RPC_ENV_NAME, DEFAULT_BASE_RPC_URL));

    uint256 public moonbeamForkId =
        vm.createFork("https://rpc.api.moonbeam.network");

    address public constant voter = address(100_000_000);

    function setUp() public {
        vm.selectFork(baseForkId);
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        proposals = new TestProposals(mips);
        proposals.setUp();
        proposals.testProposals(
            true,
            true,
            false,
            false,
            true,
            true,
            false,
            true
        ); /// only setup after deploy, build, and run, do not validate
        addresses = proposals.addresses();

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
        vm.selectFork(baseForkId);
        artemisQueuePayload = CrossChainProposal(
            address(proposals.proposals(0))
        ).getArtemisGovernorCalldata(
                addresses.getAddress("TEMPORAL_GOVERNOR"), /// call temporal gov on base
                addresses.getAddress( /// call wormhole on moonbeam
                    "WORMHOLE_CORE",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            );

        console.log("artemis governor queue governance calldata");
        emit log_bytes(artemisQueuePayload);

        vm.selectFork(moonbeamForkId);
        testMintSelf();
        vm.prank(voter);
        (bool success, bytes memory errorString) = address(governor).call(
            artemisQueuePayload
        );

        require(success, string(errorString));

        uint256 proposalId = governor.proposalCount();

        vm.warp(governor.votingDelay() + block.timestamp + 1); /// now active

        vm.prank(voter);
        governor.castVote(proposalId, 0); /// VOTE YES

        vm.warp(governor.votingPeriod() + block.timestamp + 1);

        governor.queue(proposalId);

        vm.warp(block.timestamp + timelock.delay() + 1); /// finish timelock

        governor.execute(proposalId);
    }

    function testExecuteTemporalGovMessage() public {
        testQueueAndPublishMessageRawBytes();

        vm.selectFork(baseForkId);

        console.log(
            "TEMPORAL_GOVERNOR: ",
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        (
            address[] memory targets, /// contracts to call /// native token amount to send
            ,
            bytes[] memory calldatas
        ) = CrossChainProposal(address(proposals.proposals(0)))
                .getTargetsPayloadsValues();

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

        for (uint256 i = 0; i < targets.length; i++) {
            (bool success, bytes memory errorString) = targets[i].call(
                abi.encodePacked(calldatas[i])
            );
            require(success, string(errorString));
        }

        vm.stopPrank();

        proposals.testProposals(
            true,
            false,
            false,
            false,
            false,
            false,
            false,
            true
        );
    }
}

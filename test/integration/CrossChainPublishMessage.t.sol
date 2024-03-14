// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {StringUtils} from "@proposals/utils/StringUtils.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

/// @notice run this on a chainforked moonbeam node.
/// then switch over to base network to generate the calldata,
/// then switch back to moonbeam to run the test with the generated calldata
contract CrossChainPublishMessageTest is Test, ChainIds, CreateCode {
    using StringUtils for string;

    MoonwellArtemisGovernor public governor;
    TestProposals public proposals;
    IWormhole public wormhole;
    Addresses public addresses;
    Timelock public timelock;
    Well public well;

    event LogMessagePublished(
        address indexed sender,
        uint64 sequence,
        uint32 nonce,
        bytes payload,
        uint8 consistencyLevel
    );

    string public constant BASE_RPC_ENV_NAME = "BASE_RPC_URL";
    string public constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    uint256 public baseForkId =
        vm.createFork(vm.envOr(BASE_RPC_ENV_NAME, DEFAULT_BASE_RPC_URL));

    uint256 public moonbeamForkId =
        vm.createFork("https://rpc.api.moonbeam.network");

    address public constant voter = address(100_000_000);

    function setUp() public {
        vm.selectFork(baseForkId);

        string memory path = getPath();
        // Run all pending proposals before doing e2e tests
        address[] memory mips = new address[](1);

        if (keccak256(bytes(path)) == '""' || bytes(path).length == 0) {
            /// empty string on both mac and unix, no proposals to run
            mips = new address[](0);

            proposals = new TestProposals(mips);
        } else if (path.hasChar(",")) {
            string[] memory mipPaths = path.split(",");
            if (mipPaths.length < 2) {
                revert(
                    "Invalid path(s) provided. If you want to deploy a single mip, do not use a comma."
                );
            }
            mips = new address[](mipPaths.length); /// expand mips size if multiple mips

            /// guzzle all of the memory, quadratic cost, but we don't care
            for (uint256 i = 0; i < mipPaths.length; i++) {
                /// deploy each mip and add it to the array
                bytes memory code = getCode(mipPaths[i]);

                mips[i] = deployCode(code);
            }
            proposals = new TestProposals(mips);
        } else {
            bytes memory code = getCode(path);
            mips[0] = deployCode(code);
            proposals = new TestProposals(mips);
        }

        proposals.setUp();
        /// run all proposal steps
        proposals.testProposals(
            false, /// do not log debug output
            /// -------------------------------
            true, /// do deploy
            true, /// do after deploy
            true, /// do after deploy setup
            true, /// do build
            /// -------------------------------
            false, /// do not run,
            false, /// do not teardown,
            false /// do not validate
        ); /// only setup, after deploy, build, do not validate, run, teardown

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
        if (proposals.nProposals() == 0) {
            /// if no proposals to execute, return
            return;
        }

        for (uint256 i = 0; i < proposals.nProposals(); i++) {
            bytes memory artemisQueuePayload = CrossChainProposal(
                address(proposals.proposals(i))
            ).getArtemisGovernorCalldata(
                    addresses.getAddress("TEMPORAL_GOVERNOR"), /// call temporal gov on base
                    addresses.getAddress( /// call wormhole on moonbeam
                            "WORMHOLE_CORE",
                            sendingChainIdToReceivingChainId[block.chainid]
                        )
                );

            console.log("artemis governor queue governance calldata");
            emit log_bytes(artemisQueuePayload);

            /// on moonbeam network so this should return proper addresses
            address moonbeamTimelock = addresses.getAddress(
                "MOONBEAM_TIMELOCK",
                moonBeamChainId
            );
            address wormholeCore = addresses.getAddress(
                "WORMHOLE_CORE",
                moonBeamChainId
            );
            address temporalGov = addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                baseChainId
            );

            /// iterate over and execute all proposals consecutively
            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory payloads
            ) = CrossChainProposal(address(proposals.proposals(i)))
                    .getTargetsPayloadsValues();

            vm.selectFork(moonbeamForkId);
            testMintSelf();
            vm.prank(voter);
            (bool success, ) = address(governor).call(artemisQueuePayload);

            require(success, "proposing gov proposal on moonbeam failed");

            /// -----------------------------------------------------------
            /// -----------------------------------------------------------
            /// ---------------- ADDRESS SANITY CHECKS --------------------
            /// -----------------------------------------------------------
            /// -----------------------------------------------------------

            require(
                moonbeamTimelock != address(0),
                "invalid moonbeam timelock address"
            );
            require(
                wormholeCore != address(0),
                "invalid temporal governor address"
            );
            require(
                temporalGov != address(0),
                "invalid temporal governor address"
            );

            uint256 proposalId = governor.proposalCount();

            uint64 nextSequence = IWormhole(wormhole).nextSequence(
                moonbeamTimelock
            );
            vm.warp(governor.votingDelay() + block.timestamp + 1); /// now active

            vm.prank(voter);
            governor.castVote(proposalId, 0); /// VOTE YES

            vm.warp(governor.votingPeriod() + block.timestamp + 1);

            governor.queue(proposalId);

            vm.warp(block.timestamp + timelock.delay() + 1); /// finish timelock

            bytes memory temporalGovExecData = abi.encode(
                temporalGov,
                targets,
                values,
                payloads
            );

            vm.expectEmit(true, true, true, true, wormholeCore);

            /// event LogMessagePublished(address indexed sender, uint64 sequence, uint32 nonce, bytes payload, uint8 consistencyLevel)
            emit LogMessagePublished(
                moonbeamTimelock,
                nextSequence,
                0, /// nonce is hardcoded at 0 in CrossChainProposal.sol
                temporalGovExecData,
                200 /// consistency level is hardcoded at 200 in CrossChainProposal.sol
            );
            governor.execute(proposalId);

            vm.selectFork(baseForkId); /// switch to base fork
        }
    }

    function testExecuteTemporalGovMessage() public {
        testQueueAndPublishMessageRawBytes();

        if (proposals.nProposals() == 0) {
            /// if no proposals to execute, return
            return;
        }

        console.log(
            "TEMPORAL_GOVERNOR: ",
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        for (uint256 j = 0; j < proposals.nProposals(); j++) {
            (
                address[] memory targets, /// contracts to call /// native token amount to send is ignored as temporal gov cannot accept eth
                ,
                bytes[] memory calldatas
            ) = CrossChainProposal(address(proposals.proposals(j)))
                    .getTargetsPayloadsValues();

            vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));

            for (uint256 i = 0; i < targets.length; i++) {
                (bool success, bytes memory errorString) = targets[i].call(
                    abi.encodePacked(calldatas[i])
                );
                require(success, string(errorString));
            }

            vm.stopPrank();
        }

        /// run validation on all proposals
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

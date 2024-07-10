pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";

import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {Address} from "@utils/Address.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

contract WormholeBridgeBaseUnitTest is MultichainBaseTest {
    using Address for address;

    event ProposalCanceled(uint256 proposalId);

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testSetup() public view {
        assertEq(voteCollection.getAllTargetChains().length, 1, "incorrect target chains vote collection");
        assertEq(governor.getAllTargetChains().length, 1, "incorrect target chains multichain governor");
    }

    function testTrustedSenderCorrectInGovernor() public view {
        assertTrue(
            governor.isTrustedSender(BASE_WORMHOLE_CHAIN_ID, address(voteCollection)),
            "vote collection contract should be trusted sender from base"
        );
    }

    function testTrustedSenderCorrectInVoteCollector() public view {
        assertTrue(
            voteCollection.isTrustedSender(MOONBEAM_WORMHOLE_CHAIN_ID, address(governor)),
            "governor contract should be trusted sender from moonbeam"
        );
    }

    function testTrustedSenderInVoteCollectionFromWormholeFormat() public view {
        bytes32 trustedSenderBytes32 = bytes32(uint256(uint160(address(governor))));

        assertTrue(
            voteCollection.isTrustedSender(MOONBEAM_WORMHOLE_CHAIN_ID, trustedSenderBytes32),
            "governor contract should be trusted sender from moonbeam"
        );

        // convert back to address
        address trustedSenderAddress = address(uint160(uint256(trustedSenderBytes32)));

        assertTrue(
            voteCollection.isTrustedSender(MOONBEAM_WORMHOLE_CHAIN_ID, trustedSenderAddress),
            "vote collection contract should be trusted sender from moonbeam"
        );
    }

    function testTrustedSenderInGovernorFromWormholeFormat() public view {
        bytes32 trustedSenderBytes32 = bytes32(uint256(uint160(address(voteCollection))));

        assertTrue(
            governor.isTrustedSender(BASE_WORMHOLE_CHAIN_ID, trustedSenderBytes32),
            "vote collection contract should be trusted sender from base"
        );

        // convert back to address
        address trustedSenderAddress = address(uint160(uint256(trustedSenderBytes32)));

        assertTrue(
            governor.isTrustedSender(BASE_WORMHOLE_CHAIN_ID, trustedSenderAddress),
            "vote collection contract should be trusted sender from base"
        );
    }

    /// receiveWormholeMessages failure tests
    /// value
    function testReceiveWormholeMessageFailsWithValue() public {
        vm.deal(address(this), 100);

        vm.expectRevert("WormholeBridge: no value allowed");
        voteCollection.receiveWormholeMessages{value: 100}(
            "", new bytes[](0), address(this).toBytes(), MOONBEAM_WORMHOLE_CHAIN_ID, bytes32(type(uint256).max)
        );

        vm.expectRevert("WormholeBridge: no value allowed");
        governor.receiveWormholeMessages{value: 100}(
            "", new bytes[](0), address(this).toBytes(), MOONBEAM_WORMHOLE_CHAIN_ID, bytes32(type(uint256).max)
        );
    }

    /// not relayer address
    function testReceiveWormholeMessageFailsNotRelayer() public {
        vm.expectRevert("WormholeBridge: only relayer allowed");
        voteCollection.receiveWormholeMessages{value: 0}(
            "", new bytes[](0), address(this).toBytes(), MOONBEAM_WORMHOLE_CHAIN_ID, bytes32(type(uint256).max)
        );

        vm.expectRevert("WormholeBridge: only relayer allowed");
        governor.receiveWormholeMessages{value: 0}(
            "", new bytes[](0), address(this).toBytes(), BASE_WORMHOLE_CHAIN_ID, bytes32(type(uint256).max)
        );
    }

    function testAlreadyProcessedMessageReplayFails() public {
        uint256 proposalId = testReceiveWormholeMessageSucceeds();

        bytes memory payloadVoteCollection = abi.encode(proposalId, 0, 0, 0, 0);

        vm.startPrank(address(governor.wormholeRelayer()));

        vm.expectRevert("MultichainVoteCollection: proposal already exists");
        voteCollection.receiveWormholeMessages{value: 0}(
            payloadVoteCollection,
            new bytes[](0),
            /// field unchecked in contract
            address(governor).toBytes(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bytes32(type(uint256).max)
        );

        bytes memory payloadGovernor = abi.encode(proposalId, 0, 0, 0);
        vm.expectRevert("WormholeBridge: message already processed");
        governor.receiveWormholeMessages{value: 0}(
            payloadGovernor,
            new bytes[](0),
            /// field unchecked in contract
            address(voteCollection).toBytes(),
            BASE_WORMHOLE_CHAIN_ID,
            bytes32(type(uint256).max)
        );
    }

    function testReceiveWormholeMessageSucceeds() public returns (uint256 proposalId) {
        proposalId = _createProposal();
        bytes memory payload = abi.encode(proposalId, 0, 0, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        vm.prank(address(governor.wormholeRelayer()));
        governor.receiveWormholeMessages{value: 0}(
            payload,
            new bytes[](0),
            /// field unchecked in contract
            address(voteCollection).toBytes(),
            BASE_WORMHOLE_CHAIN_ID,
            bytes32(type(uint256).max)
        );
    }

    function _createProposal() private returns (uint256) {
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        string memory description = "Proposal MIP-M00 - Update Proposal Threshold";

        targets[0] = address(governor);
        values[0] = 0;
        calldatas[0] = abi.encodeWithSignature("updateProposalThreshold(uint256)", 100_000_000 * 1e18);

        uint256 bridgeCost = governor.bridgeCostAll();
        vm.deal(address(this), bridgeCost);

        return governor.propose{value: bridgeCost}(targets, values, calldatas, description);
    }
}

pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {Address} from "@utils/Address.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {VaaHelper} from "@test/helper/VaaHelper.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";

contract WormholeBridgeBaseUnitTest is MultichainBaseTest {
    using Address for address;
    uint64 internal _vaaSeq;

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
        assertEq(
            voteCollection.getAllTargetChains().length,
            1,
            "incorrect target chains vote collection"
        );
        assertEq(
            governor.getAllTargetChains().length,
            1,
            "incorrect target chains multichain governor"
        );
    }

    function testTrustedSenderCorrectInGovernor() public view {
        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                address(voteCollection)
            ),
            "vote collection contract should be trusted sender from base"
        );
    }

    function testTrustedSenderCorrectInVoteCollector() public view {
        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                address(governor)
            ),
            "governor contract should be trusted sender from moonbeam"
        );
    }

    function testTrustedSenderInVoteCollectionFromWormholeFormat() public view {
        bytes32 trustedSenderBytes32 = bytes32(
            uint256(uint160(address(governor)))
        );

        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                trustedSenderBytes32
            ),
            "governor contract should be trusted sender from moonbeam"
        );

        // convert back to address
        address trustedSenderAddress = address(
            uint160(uint256(trustedSenderBytes32))
        );

        assertTrue(
            voteCollection.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                trustedSenderAddress
            ),
            "vote collection contract should be trusted sender from moonbeam"
        );
    }

    function testTrustedSenderInGovernorFromWormholeFormat() public view {
        bytes32 trustedSenderBytes32 = bytes32(
            uint256(uint160(address(voteCollection)))
        );

        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                trustedSenderBytes32
            ),
            "vote collection contract should be trusted sender from base"
        );

        // convert back to address
        address trustedSenderAddress = address(
            uint160(uint256(trustedSenderBytes32))
        );

        assertTrue(
            governor.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                trustedSenderAddress
            ),
            "vote collection contract should be trusted sender from base"
        );
    }

    /// executeVAAv1 failure tests
    /// value
    function testExecuteVAAv1FailsWithValue() public {
        bytes memory vaa = VaaHelper.craftVaa(
            voteCollection.coreBridge(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(governor),
            _vaaSeq++,
            ""
        );

        vm.deal(address(this), 100);
        vm.expectRevert("WormholeBridge: no value allowed");
        voteCollection.executeVAAv1{value: 100}(vaa);
    }

    /// untrusted sender
    function testExecuteVAAv1FailsUntrustedSender() public {
        bytes memory vaa = VaaHelper.craftVaa(
            voteCollection.coreBridge(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(0xdead), // untrusted
            _vaaSeq++,
            ""
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        voteCollection.executeVAAv1(vaa);
    }

    function testReplayProtectionPreventsDoubleProcessing() public {
        uint256 proposalId = testExecuteVAAv1Succeeds();

        bytes memory payload = abi.encode(proposalId, 0, 0, 0, 0);

        bytes memory vaa = VaaHelper.craftVaa(
            voteCollection.coreBridge(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(governor),
            0, // same sequence as the first VAA
            payload
        );

        vm.expectRevert("MultichainVoteCollection: proposal already exists");
        voteCollection.executeVAAv1(vaa);
    }

    function testExecuteVAAv1Succeeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposal();
        bytes memory payload = abi.encode(proposalId, 0, 0, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        bytes memory vaa = VaaHelper.craftVaa(
            governor.coreBridge(),
            BASE_WORMHOLE_CHAIN_ID,
            address(voteCollection),
            _vaaSeq++,
            payload
        );

        governor.executeVAAv1(vaa);
    }

    function _createProposal() private returns (uint256) {
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

        return
            governor.propose{value: bridgeCost}(
                targets,
                values,
                calldatas,
                description,
                new bytes[](0)
            );
    }
}

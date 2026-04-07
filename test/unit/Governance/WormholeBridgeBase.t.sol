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
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

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

    /// receiveWormholeMessages was removed from WormholeBridgeBase in V2.
    /// The function no longer exists on-chain — no revert test needed.

    /// processVAA delivers votes to governor via the mock adapter
    function testProcessVAASucceeds() public returns (uint256 proposalId) {
        proposalId = _createProposal();

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        /// Configure the mock: emitter is voteCollection on Base chain
        wormholeRelayerAdapter.setSenderChainId(BASE_WORMHOLE_CHAIN_ID);

        bytes memory innerPayload = abi.encode(proposalId, 0, 0, 0);
        bytes memory payload = abi.encode(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(governor),
            innerPayload
        );

        /// Deliver via processVAA path — emitter is voteCollection from Base
        wormholeRelayerAdapter.deliverBridgeOut(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            address(governor),
            payload,
            address(voteCollection)
        );
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
                description
            );
    }
}

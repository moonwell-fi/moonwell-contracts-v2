pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";

contract WormholeBridgeBaseUnitTest is MultichainBaseTest {
    event ProposalCanceled(uint256 proposalId);

    function setUp() public override {
        super.setUp();

        xwell.delegate(address(this));
        well.delegate(address(this));
        distributor.delegate(address(this));

        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function testSetup() public {
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

    function testTrustedSenderCorrectInGovernor() public {
        assertTrue(
            governor.isTrustedSender(baseChainId, address(voteCollection)),
            "vote collection contract should be trusted sender from base"
        );
    }

    function testTrustedSenderCorrectInVoteCollector() public {
        assertTrue(
            voteCollection.isTrustedSender(moonbeamChainId, address(governor)),
            "governor contract should be trusted sender from moonbeam"
        );
    }

    /// receiveWormholeMessages failure tests
    /// value
    function testReceiveWormholeMessageFailsWithValue() public {
        vm.deal(address(this), 100);

        vm.expectRevert("WormholeBridge: no value allowed");
        voteCollection.receiveWormholeMessages{value: 100}(
            "",
            new bytes[](0),
            addressToBytes(address(this)),
            moonbeamChainId,
            bytes32(type(uint256).max)
        );

        vm.expectRevert("WormholeBridge: no value allowed");
        governor.receiveWormholeMessages{value: 100}(
            "",
            new bytes[](0),
            addressToBytes(address(this)),
            moonbeamChainId,
            bytes32(type(uint256).max)
        );
    }

    /// not relayer address
    function testReceiveWormholeMessageFailsNotRelayer() public {
        vm.expectRevert("WormholeBridge: only relayer allowed");
        voteCollection.receiveWormholeMessages{value: 0}(
            "",
            new bytes[](0),
            addressToBytes(address(this)),
            moonbeamChainId,
            bytes32(type(uint256).max)
        );

        vm.expectRevert("WormholeBridge: only relayer allowed");
        governor.receiveWormholeMessages{value: 0}(
            "",
            new bytes[](0),
            addressToBytes(address(this)),
            baseChainId,
            bytes32(type(uint256).max)
        );
    }

    function testAlreadyProcessedMessageReplayFails() public {
        uint256 proposalId = testReceiveWormholeMessageSucceeds();

        bytes memory payloadVoteCollection = abi.encode(proposalId, 0, 0, 0, 0);

        vm.startPrank(address(governor.wormholeRelayer()));

        vm.expectRevert("MultichainVoteCollection: proposal already exists");
        voteCollection.receiveWormholeMessages{value: 0}(
            payloadVoteCollection,
            new bytes[](0), /// field unchecked in contract
            addressToBytes(address(governor)),
            moonbeamChainId,
            bytes32(type(uint256).max)
        );

        bytes memory payloadGovernor = abi.encode(proposalId, 0, 0, 0);
        vm.expectRevert("WormholeBridge: message already processed");
        governor.receiveWormholeMessages{value: 0}(
            payloadGovernor,
            new bytes[](0), /// field unchecked in contract
            addressToBytes(address(voteCollection)),
            baseChainId,
            bytes32(type(uint256).max)
        );
    }

    function testReceiveWormholeMessageSucceeds()
        public
        returns (uint256 proposalId)
    {
        proposalId = _createProposal();
        bytes memory payload = abi.encode(proposalId, 0, 0, 0);

        vm.warp(block.timestamp + governor.votingPeriod() + 1);

        vm.prank(address(governor.wormholeRelayer()));
        governor.receiveWormholeMessages{value: 0}(
            payload,
            new bytes[](0), /// field unchecked in contract
            addressToBytes(address(voteCollection)),
            baseChainId,
            bytes32(type(uint256).max)
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

    /// @notice Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    /// then to a bytes32 *left* aligns it, so we right shift to get the proper data
    /// @param addr The address to convert
    /// @return The address as a bytes32
    function addressToBytes(address addr) public pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }
}

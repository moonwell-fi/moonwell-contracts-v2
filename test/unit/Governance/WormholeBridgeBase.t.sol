pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {MultichainBaseTest} from "@test/helper/MultichainBaseTest.t.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
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
            moonbeamChainId,
            bytes32(type(uint256).max)
        );
    }

    /// TODO fill these in
    function testAlreadyProcessedMessageReplayFails(bytes32 nonce) public {}

    function testReceiveWormholeMessageSucceeds(bytes32 nonce) public {}

    /// @notice Wormhole addresses are denominated in 32 byte chunks. Converting the address to a bytes20
    /// then to a bytes32 *left* aligns it, so we right shift to get the proper data
    /// @param addr The address to convert
    /// @return The address as a bytes32
    function addressToBytes(address addr) public pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }
}

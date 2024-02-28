// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {CreateCode} from "@proposals/utils/CreateCode.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {TestMultichainProposals} from "@protocol/proposals/TestMultichainProposals.sol";
import {ITemporalGovernor, TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";

import {mipb14 as mip} from "@proposals/mips/mip-b14/mip-b14.sol";

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
    string public constant DEFAULT_BASE_RPC_URL = "https://mainnet.base.org";

    /// @notice fork ID for base
    uint256 public baseForkId =
        vm.createFork(vm.envOr("BASE_RPC_URL", DEFAULT_BASE_RPC_URL));

    string public constant DEFAULT_MOONBEAM_RPC_URL =
        "https://rpc.api.moonbeam.network";

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envOr("MOONBEAM_RPC_URL", DEFAULT_MOONBEAM_RPC_URL));

    function setUp() public override {
        super.setUp();

        vm.selectFork(moonbeamForkId);

        mip newMip = new mip();

        address[] memory proposalsArray = new address[](1);
        proposalsArray[0] = address(newMip);

        newMip.setForkIds(baseForkId, moonbeamForkId);

        /// load proposals up into the TestMultichainProposal contract
        _initialize(proposalsArray);

        runProposals(false, true, true, true, true, true, true, true);
    }

    function testSetup() public {}
}

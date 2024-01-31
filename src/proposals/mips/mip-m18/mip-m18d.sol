//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
/// After this proposal, the Temporal Governor will have 2 admins, the
/// Multichain Governor and the Artemis Timelock
contract mipm18d is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18D";

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY",
            moonBeamChainId
        );

        ITemporalGovernor.TrustedSender[]
            memory temporalGovernanceTrustedSenders = new ITemporalGovernor.TrustedSender[](
                1
            );

        temporalGovernanceTrustedSenders[0].addr = multichainGovernorAddress;
        temporalGovernanceTrustedSenders[0].chainId = moonBeamWormholeChainId;

        /// Base action

        /// add the multichain governor as a trusted sender in the wormhole bridge adapter on base
        /// this is an action that takes place on base, not on moonbeam, so flag is flipped to false for isMoonbeam
        _pushHybridAction(
            addresses.getAddress("TEMPORAL_GOVERNOR", baseChainId),
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            ),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            false
        );

        /// Moonbeam actions

        /// transfer ownership of the wormhole bridge adapter on the moonbeam chain to the multichain governor
        _pushHybridAction(
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                moonBeamChainId
            ),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            true
        );

        /// transfer ownership of proxy admin to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN", moonBeamChainId),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Moonbeam Proxy Admin to the multichain governor",
            true
        );

        /// begin transfer of ownership of the xwell token to the multichain governor
        /// This one has to go through Temporal Governance
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY", moonBeamChainId),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of the xWELL Token to the multichain governor",
            true
        );

        /// transfer ownership of chainlink oracle
        _pushHybridAction(
            addresses.getAddress("CHAINLINK_ORACLE", moonBeamChainId),
            abi.encodeWithSignature(
                "setAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Chainlink Oracle to the multichain governor",
            true
        );

        /// transfer emissions manager of safety module
        _pushHybridAction(
            addresses.getAddress("stkWELL", moonBeamChainId),
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                multichainGovernorAddress
            ),
            "Set the emissions config of the Safety Module to the multichain governor",
            true
        );

        /// set pending admin of unitroller
        _pushHybridAction(
            addresses.getAddress("UNITROLLER", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of the unitroller to the multichain governor",
            true
        );

        /// set funds admin of ecosystem reserve controller
        _pushHybridAction(
            addresses.getAddress(
                "ECOSYSTEM_RESERVE_CONTROLLER",
                moonBeamChainId
            ),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the owner of the Ecosystem Reserve Controller to the multichain governor",
            true
        );

        /// set pending admin of MOONWELL_mwBTC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mwBTC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mwBTC to the multichain governor",
            true
        );

        /// set pending admin of MOONWELL_mBUSD to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mBUSD", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mBUSD to the multichain governor",
            true
        );

        /// set pending admin of MOONWELL_mETH to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mETH to the multichain governor",
            true
        );

        /// set pending admin of MOONWELL_mUSDC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mUSDC to the multichain governor",
            true
        );

        /// set pending admin of mGLIMMER to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mGLIMMER", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mGLIMMER to the multichain governor",
            true
        );

        /// set pending admin of mxcDOT to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mxcDOT", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mxcDOT to the multichain governor",
            true
        );

        /// set pending admin of mxcUSDT to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mxcUSDT", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mxcUSDT to the multichain governor",
            true
        );

        /// set pending admin of mFRAX to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mFRAX", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mFRAX to the multichain governor",
            true
        );

        /// set pending admin of mUSDCwh to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mUSDCwh", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mUSDCwh to the multichain governor",
            true
        );

        /// set pending admin of mxcUSDC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mxcUSDC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mxcUSDC to the multichain governor",
            true
        );

        /// set pending admin of mETHwh to the multichain governor
        _pushHybridAction(
            addresses.getAddress("mETHwh", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of mETHwh to the multichain governor",
            true
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {
        /// @TODO fill this out with an actual governance flow later

        uint256 activeFork = vm.activeFork();

        vm.selectFork(moonbeamForkId);

        vm.startPrank(
            addresses.getAddress("ARTEMIS_TIMELOCK", moonBeamChainId)
        );
        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            moonbeamActions[i].target.call{value: moonbeamActions[i].value}(
                moonbeamActions[i].data
            );
        }
        vm.stopPrank();

        /// base simulation

        vm.selectFork(baseForkId);

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR", baseChainId));
        for (uint256 i = 0; i < baseActions.length; i++) {
            baseActions[i].target.call{value: baseActions[i].value}(
                baseActions[i].data
            );
        }
        vm.stopPrank();

        /// switch back to original fork
        vm.selectFork(activeFork);
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY",
            moonBeamChainId
        );

        assertEq(
            Ownable(
                addresses.getAddress(
                    "ECOSYSTEM_RESERVE_CONTROLLER",
                    moonBeamChainId
                )
            ).owner(),
            governor,
            "ecosystem reserve controller owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    moonBeamChainId
                )
            ).pendingOwner(),
            governor,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        assertEq(
            Ownable(addresses.getAddress("MOONBEAM_PROXY_ADMIN")).owner(),
            governor,
            "MOONBEAM_PROXY_ADMIN owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .pendingOwner(),
            governor,
            "xWELL_PROXY pending owner incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mETHwh")).pendingAdmin(),
            governor,
            "mETHwh pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).pendingAdmin(),
            governor,
            "mxcUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).pendingAdmin(),
            governor,
            "mUSDCwh pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mFRAX")).pendingAdmin(),
            governor,
            "mFRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).pendingAdmin(),
            governor,
            "mxcUSDT pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).pendingAdmin(),
            governor,
            "mxcDOT pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).pendingAdmin(),
            governor,
            "mGLIMMER pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            governor,
            "MOONWELL_mUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).pendingAdmin(),
            governor,
            "MOONWELL_mUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            governor,
            "MOONWELL_mETH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            governor,
            "MOONWELL_mwBTC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            governor,
            "MOONWELL_mUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            governor,
            "MOONWELL_mETH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            governor,
            "MOONWELL_mwBTC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).pendingAdmin(),
            governor,
            "UNITROLLER pending admin incorrect"
        );
    }
}

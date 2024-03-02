//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
/// After this proposal, the Temporal Governor will have 2 admins, the
/// Multichain Governor and the Artemis Timelock
contract mipm18d is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18D";

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        ITemporalGovernor.TrustedSender[]
            memory temporalGovernanceTrustedSenders = new ITemporalGovernor.TrustedSender[](
                1
            );

        temporalGovernanceTrustedSenders[0].addr = multichainGovernorAddress;
        temporalGovernanceTrustedSenders[0].chainId = moonBeamWormholeChainId;

        /// Base action

        /// add the Multichain Governor as a trusted sender in the wormhole bridge adapter on base
        /// this is an action that takes place on base, not on moonbeam, so flag is flipped to false for isMoonbeam
        _pushHybridAction(
            addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                sendingChainIdToReceivingChainId[block.chainid]
            ),
            abi.encodeWithSignature(
                "setTrustedSenders((uint16,address)[])",
                temporalGovernanceTrustedSenders
            ),
            "Add Multichain Governor as a trusted sender to the Temporal Governor",
            false
        );

        /// Moonbeam actions

        /// transfer ownership of the wormhole bridge adapter on the moonbeam chain to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of the Wormhole Bridge Adapter to the Multichain Governor",
            true
        );

        /// transfer ownership of proxy admin to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the owner of the Moonbeam Proxy Admin to the Multichain Governor",
            true
        );

        /// begin transfer of ownership of the xwell token to the Multichain Governor
        /// This one has to go through Temporal Governance
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of the xWELL Token to the Multichain Governor",
            true
        );

        /// transfer ownership of chainlink oracle
        _pushHybridAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Chainlink Oracle to the Multichain Governor",
            true
        );

        /// transfer emissions manager of safety module
        _pushHybridAction(
            addresses.getAddress("stkWELL"),
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                multichainGovernorAddress
            ),
            "Set the Emissions Config of the Safety Module to the Multichain Governor",
            true
        );

        /// set pending admin of unitroller
        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of the Unitroller to the Multichain Governor",
            true
        );

        /// set funds admin of ecosystem reserve controller
        _pushHybridAction(
            addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the owner of the Ecosystem Reserve Controller to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mwBTC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mwBTC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_mwBTC to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mBUSD to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mBUSD"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_mBUSD to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mETH to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_mETH to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mUSDC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_mUSDC to the Multichain Governor",
            true
        );

        /// set pending admin of mGLIMMER to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mGLIMMER"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mGLIMMER to the Multichain Governor",
            true
        );

        /// set pending admin of mxcDOT to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mxcDOT"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mxcDOT to the Multichain Governor",
            true
        );

        /// set pending admin of mxcUSDT to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mxcUSDT to the Multichain Governor",
            true
        );

        /// set pending admin of mFRAX to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mFRAX to the Multichain Governor",
            true
        );

        /// set pending admin of mUSDCwh to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mUSDCwh to the Multichain Governor",
            true
        );

        /// set pending admin of mxcUSDC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mxcUSDC to the Multichain Governor",
            true
        );

        /// set pending admin of mETHwh to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mETHwh"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of mETHwh to the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");
        _run(timelock, moonbeamActions);

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _run(temporalGovernor, baseActions);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        /// TODO validate the proxy admin for the ecosystem reserve proxy
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");

        assertEq(
            IStakedWellUplift(addresses.getAddress("stkWELL"))
                .EMISSION_MANAGER(),
            governor,
            "stkWELL EMISSIONS MANAGER"
        );
        assertEq(
            Ownable(addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"))
                .owner(),
            governor,
            "ecosystem reserve controller owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).pendingOwner(),
            governor,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).owner(),
            timelock,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY owner incorrect"
        );
        assertEq(
            Ownable(addresses.getAddress("MOONBEAM_PROXY_ADMIN")).owner(),
            governor,
            "MOONBEAM_PROXY_ADMIN owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .owner(),
            timelock,
            "xWELL_PROXY owner incorrect"
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
            Timelock(addresses.getAddress("mETHwh")).admin(),
            timelock,
            "mETHwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).pendingAdmin(),
            governor,
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).admin(),
            timelock,
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).pendingAdmin(),
            governor,
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).admin(),
            timelock,
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mFRAX")).pendingAdmin(),
            governor,
            "mFRAX pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mFRAX")).admin(),
            timelock,
            "mFRAX admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).pendingAdmin(),
            governor,
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).admin(),
            timelock,
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).pendingAdmin(),
            governor,
            "mxcDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).admin(),
            timelock,
            "mxcDOT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).pendingAdmin(),
            governor,
            "mGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).admin(),
            timelock,
            "mGLIMMER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            governor,
            "MOONWELL_mUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).admin(),
            timelock,
            "MOONWELL_mUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).pendingAdmin(),
            governor,
            "MOONWELL_mBUSD pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).admin(),
            timelock,
            "MOONWELL_mBUSD admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            governor,
            "MOONWELL_mwBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).admin(),
            timelock,
            "MOONWELL_mwBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            governor,
            "MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).admin(),
            timelock,
            "MOONWELL_mETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).pendingAdmin(),
            governor,
            "UNITROLLER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).admin(),
            timelock,
            "UNITROLLER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("CHAINLINK_ORACLE")).admin(),
            governor,
            "Chainlink oracle admin incorrect"
        );

        /// TODO check that the temporal governor now has multichain governor as a trusted sender
        /// and that the timelock is still a trusted sender
    }
}

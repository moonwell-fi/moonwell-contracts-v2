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
            "Set the admin of the Chainlink Oracle to the multichain governor",
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

        /// set pending admin of comptroller
        _pushHybridAction(
            addresses.getAddress("COMPTROLLER", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of the comptroller to the multichain governor",
            true
        );

        /// set pending admin of the vesting contract
        _pushHybridAction(
            addresses.getAddress(
                "TOKEN_SALE_DISTRIBUTOR_PROXY",
                moonBeamChainId
            ),
            abi.encodeWithSignature(
                "setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of the vesting contract to the multichain governor",
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

        /// TODO all of these .mad asset addresses are broken and we need to fix them for this gov proposal to work

        /// set pending admin of the MTokens
        _pushHybridAction(
            addresses.getAddress("madWBTC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madWBTC to the multichain governor",
            true
        );

        /// set pending admin of .mad mTokens

        /// set pending admin of madWETH to the multichain governor
        _pushHybridAction(
            addresses.getAddress("madWETH", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madWETH to the multichain governor",
            true
        );

        /// set pending admin of madUSDC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("madUSDC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madUSDC to the multichain governor",
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

        /// set pending admin of MGLIMMER to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MGLIMMER", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MGLIMMER to the multichain governor",
            true
        );

        /// set pending admin of MDOT to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MDOT", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MDOT to the multichain governor",
            true
        );

        /// set pending admin of MUSDT to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MUSDT", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MUSDT to the multichain governor",
            true
        );

        /// set pending admin of MFRAX to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MFRAX", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MFRAX to the multichain governor",
            true
        );

        /// set pending admin of MUSDC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MUSDC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MUSDC to the multichain governor",
            true
        );

        /// set pending admin of MXCUSDC to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MXCUSDC", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MXCUSDC to the multichain governor",
            true
        );

        /// set pending admin of METHWH to the multichain governor
        _pushHybridAction(
            addresses.getAddress("METHWH", moonBeamChainId),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of METHWH to the multichain governor",
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
            Timelock(addresses.getAddress("METHWH")).pendingAdmin(),
            governor,
            "METHWH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MXCUSDC")).pendingAdmin(),
            governor,
            "MXCUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MUSDC")).pendingAdmin(),
            governor,
            "MUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MFRAX")).pendingAdmin(),
            governor,
            "MFRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MUSDT")).pendingAdmin(),
            governor,
            "MUSDT pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MDOT")).pendingAdmin(),
            governor,
            "MDOT pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MGLIMMER")).pendingAdmin(),
            governor,
            "MGLIMMER pending admin incorrect"
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
            Timelock(addresses.getAddress("madUSDC")).pendingAdmin(),
            governor,
            "madUSDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("madWETH")).pendingAdmin(),
            governor,
            "madWETH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("madWBTC")).pendingAdmin(),
            governor,
            "madWBTC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"))
                .pendingAdmin(),
            governor,
            "TOKEN_SALE_DISTRIBUTOR_PROXY pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("COMPTROLLER")).pendingAdmin(),
            governor,
            "COMPTROLLER pending admin incorrect"
        );
    }
}

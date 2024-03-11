//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to accept governance powers, finalizing
/// the transfer of admin and owner from the current Artemis Timelock to the
/// new Multichain Governor.
/// DO_VALIDATE=true DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRINT=true forge script
/// src/proposals/mips/mip-m18/mip-m18e.sol:mipm18e
contract Proposal1 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18E";

    constructor() {
        _setProposalDescription(
            bytes("Transfer lending system Moonbase ownership")
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        /// accept admin of comptroller
        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of the comptroller as Multichain Governor",
            true
        );

        /// accept admin of .mad mTokens
        /// accept admin of MOONWELL_WBTC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_WBTC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_WETH
        _pushHybridAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_WETH as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_USDC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_USDC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_USDT
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_USDT as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_GLIMMER
        _pushHybridAction(
            addresses.getAddress("MOONWELL_GLIMMER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mGLIMMER as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_FRAX
        _pushHybridAction(
            addresses.getAddress("MOONWELL_FRAX"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_FRAX as Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamArtemisGovernor(
            addresses.getAddress("WORMHOLE_CORE"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            addresses.getAddress("WELL"),
            address(100000000)
        );
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MOONBEAM_TIMELOCK");
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).admin(),
            governor,
            "MOONWELL_WETH admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).pendingAdmin(),
            address(0),
            "MOONWELL_WETH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WBTC")).admin(),
            governor,
            "MOONWELL_WBTC admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WBTC")).pendingAdmin(),
            address(0),
            "MOONWELL_WBTC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).admin(),
            governor,
            "MOONWELL_USDC admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).pendingAdmin(),
            address(0),
            "MOONWELL_USDC pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).admin(),
            governor,
            "MOONWELL_USDT admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).pendingAdmin(),
            address(0),
            "MOONWELL_USDT pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).admin(),
            governor,
            "MOONWELL_GLIMMER admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).pendingAdmin(),
            address(0),
            "MOONWELL_GLIMMER pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).admin(),
            governor,
            "MOONWELL_FRAX admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).pendingAdmin(),
            address(0),
            "MOONWELL_FRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).pendingAdmin(),
            address(0),
            "UNITROLLER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("UNITROLLER")).admin(),
            governor,
            "UNITROLLER admin incorrect"
        );
    }
}

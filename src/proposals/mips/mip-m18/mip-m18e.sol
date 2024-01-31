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
contract mipm18e is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18E";

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR"
        );
        // bytes memory wormholeTemporalGovPayload = abi.encodeWithSignature(
        //     "publishMessage(uint32,bytes,uint8)",
        //     nonce,
        //     temporalGovCalldata,
        //     consistencyLevel
        // );
        /// TODO add multichain governor as wormhole trusted sender in temporal governor

        /// Moonbeam actions

        /// transfer ownership of the wormhole bridge adapter on the moonbeam chain to the multichain governor
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept admin of the Wormhole Bridge Adapter as multichain governor",
            true
        );

        /// TODO refactor this into a base action
        /// remove the artemis timelock as a trusted sender in the wormhole bridge adapter on base
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_CORE"),
            abi.encodeWithSignature(
                "publishMessage(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Wormhole Bridge Adapter as the multichain governor",
            true
        );

        /// begin transfer of ownership of the xwell token to the multichain governor
        /// This one has to go through Temporal Governance
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept owner of the xWELL Token as the multichain governor",
            true
        );

        /// set pending admin of comptroller
        _pushHybridAction(
            addresses.getAddress("COMPTROLLER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of the comptroller as multichain governor",
            true
        );

        /// accept pending admin of the vesting contract
        _pushHybridAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            abi.encodeWithSignature("acceptPendingAdmin()"),
            "Accept pending admin of the vesting contract as the multichain governor",
            true
        );

        /// set pending admin of the MTokens
        _pushHybridAction(
            addresses.getAddress("madWBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept the pending owner of madWBTC to the multichain governor",
            true
        );

        /// set pending admin of .mad mTokens

        _pushHybridAction(
            addresses.getAddress("madWETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of madWETH as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("madUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of madUSDC as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mwBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mwBTC as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mETH as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mUSDC as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MGLIMMER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MGLIMMER as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MDOT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Set Accept admin MDOT to as multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MUSDT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Set Accept admin MUSDT to as multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MFRAX"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Set Accept admin MFRAX to as multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Set Accept admin MUSDC to as multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MXCUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MXCUSDC as the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("METHWH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of METHWH as the multichain governor",
            true
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).pendingOwner(),
            address(0),
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).owner(),
            governor,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY owner incorrect"
        );

        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .pendingOwner(),
            address(0),
            "xWELL_PROXY pending owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .owner(),
            governor,
            "xWELL_PROXY owner incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("METHWH")).admin(),
            governor,
            "METHWH admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("METHWH")).pendingAdmin(),
            address(0),
            "METHWH pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MXCUSDC")).pendingAdmin(),
            address(0),
            "MXCUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MXCUSDC")).admin(),
            governor,
            "MXCUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MUSDC")).pendingAdmin(),
            address(0),
            "MUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MUSDC")).admin(),
            governor,
            "MUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MFRAX")).admin(),
            governor,
            "MFRAX admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MFRAX")).pendingAdmin(),
            address(0),
            "MFRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MUSDT")).pendingAdmin(),
            address(0),
            "MUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MUSDT")).admin(),
            governor,
            "MUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MDOT")).pendingAdmin(),
            address(0),
            "MDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MDOT")).admin(),
            governor,
            "MDOT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MGLIMMER")).pendingAdmin(),
            address(0),
            "MGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MGLIMMER")).admin(),
            governor,
            "MGLIMMER admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).pendingAdmin(),
            address(0),
            "MOONWELL_mUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mUSDC")).admin(),
            governor,
            "MOONWELL_mUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            address(0),
            "MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).admin(),
            governor,
            "MOONWELL_mETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).pendingAdmin(),
            address(0),
            "MOONWELL_mwBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mwBTC")).admin(),
            governor,
            "MOONWELL_mwBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("madUSDC")).pendingAdmin(),
            address(0),
            "madUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("madUSDC")).admin(),
            governor,
            "madUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("madWETH")).pendingAdmin(),
            address(0),
            "madWETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("madWETH")).admin(),
            governor,
            "madWETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("madWBTC")).pendingAdmin(),
            address(0),
            "madWBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("madWBTC")).admin(),
            governor,
            "madWBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"))
                .pendingAdmin(),
            address(0),
            "TOKEN_SALE_DISTRIBUTOR_PROXY pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"))
                .admin(),
            governor,
            "TOKEN_SALE_DISTRIBUTOR_PROXY admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("COMPTROLLER")).pendingAdmin(),
            address(0),
            "COMPTROLLER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("COMPTROLLER")).admin(),
            governor,
            "COMPTROLLER admin incorrect"
        );
    }
}

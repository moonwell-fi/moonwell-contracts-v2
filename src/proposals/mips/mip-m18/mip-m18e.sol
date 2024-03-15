//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {ITokenSaleDistributorProxy} from "../../../tokensale/ITokenSaleDistributorProxy.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
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
contract mipm18e is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18E";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m18/MIP-M18-E.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        ITemporalGovernor.TrustedSender[]
            memory trustedSendersToRemove = new ITemporalGovernor.TrustedSender[](
                1
            );

        trustedSendersToRemove[0].addr = addresses.getAddress(
            "MOONBEAM_TIMELOCK"
        );
        trustedSendersToRemove[0].chainId = moonBeamWormholeChainId;

        /// Base action

        /// remove the artemis timelock as a trusted sender in the wormhole bridge adapter on base
        _pushHybridAction(
            addresses.getAddress(
                "TEMPORAL_GOVERNOR",
                sendingChainIdToReceivingChainId[block.chainid]
            ),
            abi.encodeWithSignature(
                "unSetTrustedSenders((uint16,address)[])",
                trustedSendersToRemove
            ),
            "Remove Artemis Timelock as a trusted sender in the Temporal Governor on Base",
            false
        );

        /// Moonbeam actions

        /// transfer ownership of the wormhole bridge adapter on the moonbeam chain to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept admin of the Wormhole Bridge Adapter as Multichain Governor",
            true
        );

        /// accept transfer of ownership of the xwell token to the Multichain Governor
        /// This one has to go through Temporal Governance
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept owner of the xWELL Token as the Multichain Governor",
            true
        );

        /// accept admin of comptroller
        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of the comptroller as Multichain Governor",
            true
        );

        /// accept admin of .mad mTokens

        /// accept admin of MOONWELL_mwBTC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mwBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mwBTC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mBUSD
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mBUSD"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mBUSD as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mETH
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mETH as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mUSDC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mUSDC as the Multichain Governor",
            true
        );

        /// accept admin of mGLIMMER
        _pushHybridAction(
            addresses.getAddress("mGLIMMER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mGLIMMER as the Multichain Governor",
            true
        );

        /// accept admin of mxcDOT
        _pushHybridAction(
            addresses.getAddress("mxcDOT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mxcDOT as Multichain Governor",
            true
        );

        /// accept admin of mxcUSDT
        _pushHybridAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mxcUSDT as Multichain Governor",
            true
        );

        /// accept admin of mFRAX
        _pushHybridAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mFRAX as Multichain Governor",
            true
        );

        /// accept admin of mUSDCwh
        _pushHybridAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mUSDCwh as Multichain Governor",
            true
        );

        /// accept admin of mxcUSDC
        _pushHybridAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mxcUSDC as the Multichain Governor",
            true
        );

        /// accept admin of mETHwh
        _pushHybridAction(
            addresses.getAddress("mETHwh"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of mETHwh as the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(moonbeamForkId);
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
            Timelock(addresses.getAddress("mETHwh")).admin(),
            governor,
            "mETHwh admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mETHwh")).pendingAdmin(),
            address(0),
            "mETHwh pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).pendingAdmin(),
            address(0),
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDC")).admin(),
            governor,
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).pendingAdmin(),
            address(0),
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mUSDCwh")).admin(),
            governor,
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mFRAX")).admin(),
            governor,
            "mFRAX admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mFRAX")).pendingAdmin(),
            address(0),
            "mFRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).pendingAdmin(),
            address(0),
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcUSDT")).admin(),
            governor,
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).pendingAdmin(),
            address(0),
            "mxcDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mxcDOT")).admin(),
            governor,
            "mxcDOT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).pendingAdmin(),
            address(0),
            "mGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("mGLIMMER")).admin(),
            governor,
            "mGLIMMER admin incorrect"
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
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).pendingAdmin(),
            address(0),
            "MOONWELL_mBUSD pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mBUSD")).admin(),
            governor,
            "MOONWELL_mBUSD admin incorrect"
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

        vm.selectFork(baseForkId);

        // check that the multichain governor now is the only trusted sender on the temporal governor
        TemporalGovernor temporalGovernor = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        bytes32[] memory trustedSenders = temporalGovernor.allTrustedSenders(
            chainIdToWormHoleId[block.chainid]
        );

        assertEq(trustedSenders.length, 1);

        assertTrue(
            temporalGovernor.isTrustedSender(
                chainIdToWormHoleId[block.chainid],
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "MultichainGovernor not trusted sender"
        );

        vm.selectFork(moonbeamForkId);
    }
}

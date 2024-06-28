//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {ForkID} from "@utils/Enums.sol";

/// Proposal to run on Moonbeam to accept governance powers, finalizing
/// the transfer of admin and owner from the current Artemis Timelock to the
/// new Multichain Governor.
/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m24/mip-m24.sol:mipm24
contract mipm24 is HybridProposal, MultichainGovernorDeploy {
    string public constant override name = "MIP-M24";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m24/MIP-M24.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 1;
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Moonbeam;
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

        /// accept admin of DEPRECATED_MOONWELL_mWBTC
        _pushHybridAction(
            addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of DEPRECATED_MOONWELL_mWBTC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mBUSD
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mBUSD"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mBUSD as the Multichain Governor",
            true
        );

        /// accept admin of DEPRECATED_MOONWELL_mETH
        _pushHybridAction(
            addresses.getAddress("DEPRECATED_MOONWELL_mETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of DEPRECATED_MOONWELL_mETH as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mUSDC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mUSDC as the Multichain Governor",
            true
        );

        /// accept admin of MNATIVE
        _pushHybridAction(
            addresses.getAddress("MNATIVE"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MNATIVE as the Multichain Governor",
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

        /// accept admin of MOONWELL_mETH
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_mETH as the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(uint256(primaryForkId()));

        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(uint256(ForkID.Base));

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(addresses, temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(uint256(primaryForkId()));
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
            Timelock(addresses.getAddress("MOONWELL_mETH")).admin(),
            governor,
            "MOONWELL_mETH admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mETH")).pendingAdmin(),
            address(0),
            "MOONWELL_mETH pending admin incorrect"
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
            Timelock(addresses.getAddress("MNATIVE")).pendingAdmin(),
            address(0),
            "MNATIVE pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MNATIVE")).admin(),
            governor,
            "MNATIVE admin incorrect"
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
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH"))
                .pendingAdmin(),
            address(0),
            "DEPRECATED_MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH")).admin(),
            governor,
            "DEPRECATED_MOONWELL_mETH admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"))
                .pendingAdmin(),
            address(0),
            "DEPRECATED_MOONWELL_mWBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC")).admin(),
            governor,
            "DEPRECATED_MOONWELL_mWBTC admin incorrect"
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

        vm.selectFork(uint256(ForkID.Base));

        // check that the multichain governor now is the only trusted sender on the temporal governor
        TemporalGovernor temporalGovernor = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
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

        vm.selectFork(uint256(primaryForkId()));
    }
}

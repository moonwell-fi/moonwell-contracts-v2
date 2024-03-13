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
        vm.selectFork(moonbeamForkId);

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
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_WBTC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mBUSD
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_USDC as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mETH
        _pushHybridAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_WETH as the Multichain Governor",
            true
        );

        /// accept admin of MOONWELL_mUSDC
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDT"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_USDT as the Multichain Governor",
            true
        );

        /// accept admin of mGLIMMER
        _pushHybridAction(
            addresses.getAddress("MOONWELL_GLIMMER"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_GLIMMER as the Multichain Governor",
            true
        );

        /// accept admin of mFRAX
        _pushHybridAction(
            addresses.getAddress("MOONWELL_FRAX"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept admin of MOONWELL_FRAX as Multichain Governor",
            true
        );

        // accept pending admin of distributor
        _pushHybridAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            abi.encodeWithSignature("acceptPendingAdmin()"),
            "Accept admin of the Token Sale Distributor as Multichain Governor",
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
            Timelock(addresses.getAddress("MOONWELL_WBTC")).admin(),
            governor,
            "mETHwh admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WBTC")).pendingAdmin(),
            address(0),
            "mETHwh pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).pendingAdmin(),
            address(0),
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).admin(),
            governor,
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).pendingAdmin(),
            address(0),
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).admin(),
            governor,
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).admin(),
            governor,
            "mFRAX admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).pendingAdmin(),
            address(0),
            "mFRAX pending admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).pendingAdmin(),
            address(0),
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).admin(),
            governor,
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).pendingAdmin(),
            address(0),
            "mxcDOT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).admin(),
            governor,
            "mxcDOT admin incorrect"
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

        assertEq(
            ITokenSaleDistributorProxy(
                addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY")
            ).admin(),
            governor,
            "TOKEN_SALE_DISTRIBUTOR_PROXY admin incorrect"
        );
        assertEq(
            ITokenSaleDistributorProxy(
                addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY")
            ).pendingAdmin(),
            address(0),
            "TOKEN_SALE_DISTRIBUTOR_PROXY pending admin incorrect"
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

        assertEq(trustedSenders[0], keccak256(abi.encodePacked(governor)));

        vm.selectFork(moonbeamForkId);
    }
}

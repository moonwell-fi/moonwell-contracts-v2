//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {ITokenSaleDistributorProxy} from "../../../tokensale/ITokenSaleDistributorProxy.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
/// After this proposal, the Temporal Governor will have 2 admins, the
/// Multichain Governor and the Artemis Timelock
/// DO_BUILD=true DO_VALIDATE=true DO_RUN=true DO_PRINT=true forge script
/// src/proposals/mips/mip-m18/mip-m18d.sol:mipm18d
contract mipm18d is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18D";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m18/MIP-M18-D.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        vm.selectFork(moonbeamForkId);

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
            addresses.getAddress("stkWELL_PROXY"),
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
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_WBTC to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mBUSD to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_USDC to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mETH to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_WETH to the Multichain Governor",
            true
        );

        /// set pending admin of MOONWELL_mUSDC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_USDT"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_USDT to the Multichain Governor",
            true
        );

        /// set pending admin of mGLIMMER to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_GLIMMER"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_GLIMMER to the Multichain Governor",
            true
        );

        /// set pending admin of mxcDOT to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_FRAX"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MOONWELL_FRAX to the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamArtemisGovernor(
            addresses.getAddress("WORMHOLE_CORE"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            addresses.getAddress("WELL"),
            address(1000000000)
        );

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");

        assertEq(
            IStakedWellUplift(addresses.getAddress("stkWELL_PROXY"))
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
            Timelock(addresses.getAddress("MOONWELL_WBTC")).pendingAdmin(),
            governor,
            "mETHwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WBTC")).admin(),
            timelock,
            "mETHwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).pendingAdmin(),
            governor,
            "mxcUSDC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_WETH")).admin(),
            timelock,
            "mxcUSDC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).pendingAdmin(),
            governor,
            "mUSDCwh pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDC")).admin(),
            timelock,
            "mUSDCwh admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).pendingAdmin(),
            governor,
            "mFRAX pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_USDT")).admin(),
            timelock,
            "mFRAX admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).pendingAdmin(),
            governor,
            "mxcUSDT pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_FRAX")).admin(),
            timelock,
            "mxcUSDT admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).pendingAdmin(),
            governor,
            "mGLIMMER pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MOONWELL_GLIMMER")).admin(),
            timelock,
            "mGLIMMER admin incorrect"
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

        vm.selectFork(baseForkId);

        // and that the timelock is still a trusted sender
        TemporalGovernor temporalGovernor = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        bytes32[] memory trustedSenders = temporalGovernor.allTrustedSenders(
            chainIdToWormHoleId[block.chainid]
        );

        assertEq(trustedSenders.length, 2);

        assertEq(trustedSenders[0], keccak256(abi.encodePacked(timelock)));

        assertEq(trustedSenders[1], keccak256(abi.encodePacked(governor)));

        validateProxy(
            vm,
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
            addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "moonbeam proxies for multichain governor"
        );

        vm.selectFork(moonbeamForkId);
    }
}

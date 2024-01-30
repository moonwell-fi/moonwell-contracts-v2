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
contract mipm18c is HybridProposal, MultichainGovernorDeploy, ChainIds {
    string public constant name = "MIP-M18D";

    /// @notice whitelisted calldata for the break glass guardian
    bytes[] public approvedCalldata;

    /// @notice whitelisted calldata for the temporal governor
    bytes[] public temporalGovernanceCalldata;

    /// @notice trusted senders for the temporal governor
    ITemporalGovernor.TrustedSender[] public temporalGovernanceTrustedSenders;

    /// TODO verify these params with Luke before code freeze

    /// @notice duration of the voting period for a proposal
    uint256 public constant votingPeriodSeconds = 3 days;

    /// @notice minimum number of votes cast required for a proposal to pass
    uint256 public constant quorum = 1_000_000 * 1e18;

    /// @notice maximum number of live proposals that a user can have
    uint256 public constant maxUserLiveProposals = 5;

    /// @notice duration of the pause
    uint128 public constant pauseDuration = 10 days;

    /// @notice address of the temporal governor
    address[] public temporalGovernanceTargets;

    /// @notice threshold of tokens required to create a proposal
    uint256 public constant proposalThreshold = 100_000_000 * 1e18;

    /// @notice duration of the cross chain vote collection period
    uint256 public constant crossChainVoteCollectionPeriod = 1 days;

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );
        address multichainVoteCollection = addresses.getAddress(
            "VOTE_COLLECTION_PROXY",
            chainIdToWormHoleId[block.chainid] /// TODO triple check this
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        /// TODO give this extra review, ensure addresses and chainids are correct
        trustedSenders[0].addr = multichainVoteCollection;
        trustedSenders[0].chainId = chainIdToWormHoleId[block.chainid];

        MultichainGovernor.InitializeData memory initData;

        initData.well = addresses.getAddress("WELL");
        initData.xWell = addresses.getAddress("xWELL_PROXY");
        initData.stkWell = addresses.getAddress("stkWELL");
        initData.distributor = addresses.getAddress(
            "TOKEN_SALE_DISTRIBUTOR_PROXY"
        );
        initData.proposalThreshold = proposalThreshold;
        initData.votingPeriodSeconds = votingPeriodSeconds;
        initData
            .crossChainVoteCollectionPeriod = crossChainVoteCollectionPeriod;
        initData.quorum = quorum;
        initData.maxUserLiveProposals = maxUserLiveProposals;
        initData.pauseDuration = pauseDuration;

        initData.pauseGuardian = addresses.getAddress(
            "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
        );
        initData.breakGlassGuardian = addresses.getAddress(
            "BREAK_GLASS_GUARDIAN"
        );
        initData.wormholeRelayer = addresses.getAddress(
            "WORMHOLE_BRIDGE_RELAYER"
        );

        governor.initialize(initData, trustedSenders, approvedCalldata);
    }

    function afterDeploySetup(Addresses addresses) public override {}

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
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            true
        );

        /// TODO refactor this out
        /// add the multichain governor as a trusted sender in the wormhole bridge adapter on base
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_CORE"),
            abi.encodeWithSignature(
                "publishMessage(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            true
        );

        /// transfer ownership of proxy admin to the multichain governor
        _pushHybridAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
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
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of the xWELL Token to the multichain governor",
            true
        );

        /// transfer ownership of chainlink oracle
        _pushHybridAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the admin of the Chainlink Oracle to the multichain governor",
            true
        );

        /// transfer emissions manager of safety module
        _pushHybridAction(
            addresses.getAddress("stkWELL"),
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                multichainGovernorAddress
            ),
            "Set the emissions config of the Safety Module to the multichain governor",
            true
        );

        /// set pending admin of comptroller
        _pushHybridAction(
            addresses.getAddress("COMPTROLLER"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of the comptroller to the multichain governor",
            true
        );

        /// set pending admin of the vesting contract
        _pushHybridAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of the vesting contract to the multichain governor",
            true
        );

        /// set funds admin of ecosystem reserve controller
        _pushHybridAction(
            addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"),
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            ),
            "Set the owner of the Ecosystem Reserve Controller to the multichain governor",
            true
        );

        /// set pending admin of the MTokens
        _pushHybridAction(
            addresses.getAddress("madWBTC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madWBTC to the multichain governor",
            true
        );

        /// set pending admin of .mad mTokens

        _pushHybridAction(
            addresses.getAddress("madWETH"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madWETH to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("madUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of madUSDC to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mwBTC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mwBTC to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mETH"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mETH to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MOONWELL_mUSDC to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MGLIMMER"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MGLIMMER to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MDOT"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MDOT to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MUSDT"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MUSDT to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MFRAX"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MFRAX to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MUSDC to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MXCUSDC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending owner of MXCUSDC to the multichain governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("METHWH"),
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
        /// @dev enable debugging
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

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

        /// TODO validate pending admin
    }
}

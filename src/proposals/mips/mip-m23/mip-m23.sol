//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {MToken} from "@protocol/MToken.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
/// After this proposal, the Temporal Governor will have 2 admins, the
/// Multichain Governor and the Artemis Timelock
/// DO_BUILD=true DO_VALIDATE=true DO_RUN=true DO_PRINT=true forge script
/// src/proposals/mips/mip-m23/mip-m23.sol:mipm23
contract mipm23 is Configs, HybridProposal, MultichainGovernorDeploy {
    string public constant override name = "MIP-M23";

    /// @notice new xWELL buffer cap
    uint256 public constant XWELL_BUFFER_CAP = 100_000_000 * 1e18;

    /// @notice new xWELL rate limit per second
    uint128 public constant XWELL_RATE_LIMIT_PER_SECOND = 1158 * 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m23/MIP-M23.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (PrimaryFork) {
        return PrimaryFork.Moonbeam;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        vm.selectFork(uint256(primaryForkId()));

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

        /// adjust rate limits to allow initial transfers through
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"), /// address is the same on both chains
            abi.encodeWithSignature(
                "setBufferCap(address,uint256)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                XWELL_BUFFER_CAP
            ),
            "Set the buffer cap of the wormhole bridge adapter to 100m",
            true
        );
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"), /// address is the same on both chains
            abi.encodeWithSignature(
                "setBufferCap(address,uint256)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                XWELL_BUFFER_CAP
            ),
            "Set the buffer cap of the wormhole bridge adapter to 100m",
            false
        );
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"), /// address is the same on both chains
            abi.encodeWithSignature(
                "setRateLimitPerSecond(address,uint128)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                XWELL_RATE_LIMIT_PER_SECOND
            ),
            "Set the rate limit per second of the wormhole bridge adapter to 1158/WELL per second",
            true
        );
        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"), /// address is the same on both chains
            abi.encodeWithSignature(
                "setRateLimitPerSecond(address,uint128)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                XWELL_RATE_LIMIT_PER_SECOND
            ),
            "Set the rate limit per second of the wormhole bridge adapter to 1158/WELL per second",
            false
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
            addresses.getAddress("STK_GOVTOKEN"),
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

        /// set pending admin of DEPRECATED_MOONWELL_mWBTC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of DEPRECATED_MOONWELL_mWBTC to the Multichain Governor",
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

        /// set pending admin of DEPRECATED_MOONWELL_mETH to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("DEPRECATED_MOONWELL_mETH"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of DEPRECATED_MOONWELL_mETH to the Multichain Governor",
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

        /// set pending admin of MNATIVE to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MNATIVE"),
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            ),
            "Set the pending admin of MNATIVE to the Multichain Governor",
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

        delete cTokenConfigurations[block.chainid]; /// wipe existing mToken Configs.sol
        delete emissions[block.chainid]; /// wipe existing reward loaded in Configs.sol

        {
            _setEmissionConfiguration(
                "./src/proposals/mips/mip-m23/mip-m23.json"
            );
        }

        /// -------------- EMISSION CONFIGURATION --------------

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        address mrd = addresses.getAddress(
            "MRD_PROXY",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                _pushHybridAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        addresses.getAddress(
                            config.mToken,
                            sendingChainIdToReceivingChainId[block.chainid]
                        ),
                        addresses.getAddress(
                            config.owner,
                            sendingChainIdToReceivingChainId[block.chainid]
                        ),
                        config.emissionToken,
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    string(
                        abi.encodePacked(
                            "Emission configuration set for ",
                            config.mToken
                        )
                    ),
                    false /// base action
                );
            }
        }
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(uint256(PrimaryFork.Base));

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(addresses, temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(uint256(primaryForkId()));
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");

        assertEq(
            IStakedWellUplift(addresses.getAddress("STK_GOVTOKEN"))
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
            Timelock(addresses.getAddress("MNATIVE")).pendingAdmin(),
            governor,
            "MNATIVE pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("MNATIVE")).admin(),
            timelock,
            "MNATIVE admin incorrect"
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
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"))
                .pendingAdmin(),
            governor,
            "DEPRECATED_MOONWELL_mWBTC pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mWBTC")).admin(),
            timelock,
            "DEPRECATED_MOONWELL_mWBTC admin incorrect"
        );

        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH"))
                .pendingAdmin(),
            governor,
            "DEPRECATED_MOONWELL_mETH pending admin incorrect"
        );
        assertEq(
            Timelock(addresses.getAddress("DEPRECATED_MOONWELL_mETH")).admin(),
            timelock,
            "DEPRECATED_MOONWELL_mETH admin incorrect"
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

        assertEq(
            xWELL(addresses.getAddress("xWELL_PROXY")).bufferCap(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            XWELL_BUFFER_CAP,
            "xWELL buffer cap incorrect"
        );
        assertEq(
            xWELL(addresses.getAddress("xWELL_PROXY")).rateLimitPerSecond(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            XWELL_RATE_LIMIT_PER_SECOND,
            "xWELL rate limit per second incorrect"
        );

        vm.selectFork(uint256(PrimaryFork.Base));

        assertEq(
            xWELL(addresses.getAddress("xWELL_PROXY")).bufferCap(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            XWELL_BUFFER_CAP,
            "xWELL buffer cap incorrect"
        );
        assertEq(
            xWELL(addresses.getAddress("xWELL_PROXY")).rateLimitPerSecond(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            XWELL_RATE_LIMIT_PER_SECOND,
            "xWELL rate limit per second incorrect"
        );

        TemporalGovernor temporalGovernor = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );

        assertTrue(
            temporalGovernor.isTrustedSender(
                chainIdToWormHoleId[block.chainid],
                addresses.getAddress(
                    "MOONBEAM_TIMELOCK",
                    sendingChainIdToReceivingChainId[block.chainid]
                )
            ),
            "timelock not trusted sender"
        );

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

        validateProxy(
            vm,
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
            addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "moonbeam proxies for multichain governor"
        );

        /// get moonbeam chainid for the emissions as this is where the data was stored
        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            sendingChainIdToReceivingChainId[block.chainid]
        );
        MultiRewardDistributor distributor = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];
                MultiRewardDistributorCommon.MarketConfig
                    memory marketConfig = distributor.getConfigForMarket(
                        MToken(addresses.getAddress(config.mToken)),
                        config.emissionToken
                    );

                assertEq(
                    marketConfig.owner,
                    addresses.getAddress(config.owner),
                    "emission owner incorrect"
                );
                assertEq(
                    marketConfig.emissionToken,
                    config.emissionToken,
                    "emission token incorrect"
                );
                assertEq(
                    marketConfig.endTime,
                    config.endTime,
                    "end time incorrect"
                );
                assertEq(
                    marketConfig.supplyEmissionsPerSec,
                    config.supplyEmissionPerSec,
                    "supply emission per second incorrect"
                );
                assertEq(
                    marketConfig.borrowEmissionsPerSec,
                    config.borrowEmissionsPerSec,
                    "borrow emission per second incorrect"
                );
                assertEq(
                    marketConfig.supplyGlobalIndex,
                    1e36,
                    "supply global index incorrect"
                );
                assertEq(
                    marketConfig.borrowGlobalIndex,
                    1e36,
                    "borrow global index incorrect"
                );
            }
        }

        vm.selectFork(uint256(primaryForkId()));
    }
}

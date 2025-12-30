pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";

/// Helper contract to deploy MultichainGovernor, MultichainVoteCollection,
/// Ecosystem Reserve, Ecosystem Reserve Controller and StakedWell contracts
contract MultichainGovernorDeploy is Test {
    function deployMultichainGovernor(
        address proxyAdmin
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MultichainGovernor());

        console.log("proxy constructor calldata: ");
        console.logBytes(abi.encode(governorImpl, proxyAdmin, ""));

        proxy = address(
            new TransparentUpgradeableProxy(governorImpl, proxyAdmin, "")
        );
    }

    function deployMockMultichainGovernor(
        address proxyAdmin
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MockMultichainGovernor());

        proxy = address(
            new TransparentUpgradeableProxy(governorImpl, proxyAdmin, "")
        );
    }

    function initializeMultichainGovernor(
        address governorProxy,
        MultichainGovernor.InitializeData memory initializeData,
        WormholeTrustedSender.TrustedSender[] memory trustedSenders,
        bytes[] memory whitelistedCalldata
    ) public {
        MultichainGovernor(payable(governorProxy)).initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
    }

    function _deployVotingPowerAggregator(
        address xWell,
        address stkWell,
        address proxyAdmin,
        address owner
    ) internal returns (address votingPowerProxy) {
        address votingPowerImpl = address(new VotingPowerAggregator());

        bytes memory votingPowerInitData = abi.encodeWithSignature(
            "initialize(address,address)",
            owner,
            xWell
        );

        votingPowerProxy = address(
            new TransparentUpgradeableProxy(
                votingPowerImpl,
                proxyAdmin,
                votingPowerInitData
            )
        );

        // Add stkWell as a snapshot source
        vm.prank(owner);
        VotingPowerAggregator(votingPowerProxy).addSnapshotSource(stkWell);
    }

    function deployVoteCollection(
        address xWell,
        address stkWell,
        address moonbeamGovernor,
        address relayer,
        uint16 moonbeamWormholeChainId,
        address proxyAdmin,
        address owner
    ) public returns (address proxy, address voteCollectionImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint16,address)",
            xWell,
            stkWell,
            moonbeamGovernor,
            relayer,
            moonbeamWormholeChainId,
            owner
        );

        voteCollectionImpl = address(new MultichainVoteCollection());

        console.log("proxy constructor calldata vote collection: ");
        console.logBytes(abi.encode(voteCollectionImpl, proxyAdmin, initData));

        proxy = address(
            new TransparentUpgradeableProxy(
                voteCollectionImpl,
                proxyAdmin,
                initData
            )
        );
    }

    // V2 version with VotingPowerAggregator
    function deployVoteCollectionV2(
        address votingPowerAggregator,
        address xWell,
        address stkWell,
        address moonbeamGovernor,
        address relayer,
        uint16 moonbeamWormholeChainId,
        address proxyAdmin,
        address owner
    ) public returns (address proxy, address voteCollectionImpl) {
        // Deploy VotingPowerAggregator if not provided
        address votingPowerProxy = votingPowerAggregator;
        if (votingPowerProxy == address(0)) {
            votingPowerProxy = _deployVotingPowerAggregator(
                xWell,
                stkWell,
                proxyAdmin,
                owner
            );
        }

        // Deploy MultichainVoteCollectionV2 with V1 initialize (for backwards compat)
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint16,address)",
            xWell,
            stkWell,
            moonbeamGovernor,
            relayer,
            moonbeamWormholeChainId,
            owner
        );

        voteCollectionImpl = address(new MultichainVoteCollectionV2());

        console.log("proxy constructor calldata vote collection V2: ");
        console.logBytes(abi.encode(voteCollectionImpl, proxyAdmin, initData));

        proxy = address(
            new TransparentUpgradeableProxy(
                voteCollectionImpl,
                proxyAdmin,
                initData
            )
        );

        // Call initializeV2 with VotingPowerAggregator
        MultichainVoteCollectionV2(proxy).initializeV2(votingPowerProxy);
    }

    // Return values as struct to avoid stack too deep error
    struct MultichainAddresses {
        address governorProxy;
        address governorImplementation;
        address voteCollectionProxy;
        address wormholeRelayerAdapter;
        address proxyAdmin;
    }

    // V1 helper (without VotingPowerAggregator)
    function _deployVoteCollectionHelper(
        address xWell,
        address stkWell,
        address governor,
        address relayer,
        uint16 moonbeamChainId,
        address proxyAdmin,
        address owner
    ) internal returns (address vProxy) {
        (vProxy, ) = deployVoteCollection(
            xWell,
            stkWell,
            governor,
            relayer,
            moonbeamChainId,
            proxyAdmin,
            owner
        );
    }

    // V2 helper (with VotingPowerAggregator)
    function _deployVoteCollectionHelperV2(
        address xWell,
        address stkWell,
        address governor,
        address relayer,
        uint16 moonbeamChainId,
        address proxyAdmin,
        address owner
    ) internal returns (address vProxy) {
        (vProxy, ) = deployVoteCollectionV2(
            address(0), // create new VotingPowerAggregator
            xWell,
            stkWell,
            governor,
            relayer,
            moonbeamChainId,
            proxyAdmin,
            owner
        );
    }

    /// @notice for testing purposes only, not to be used in production as both
    /// contracts are deployed on the same chain (V1)
    function deployGovernorRelayerAndVoteCollection(
        MultichainGovernor.InitializeData memory initializeData,
        bytes[] memory whitelistedCalldata,
        address proxyAdmin,
        uint16 moonbeamChainId,
        uint16 baseChainId,
        address voteCollectionOwner,
        address baseStkWell
    ) public returns (MultichainAddresses memory addresses) {
        proxyAdmin = proxyAdmin == address(0)
            ? address(new ProxyAdmin())
            : proxyAdmin;

        // deploy governor
        (
            address gProxy,
            address gImplementation
        ) = deployMockMultichainGovernor(proxyAdmin);
        address wormholeRelayerAdapter = address(
            new WormholeRelayerAdapter(new uint16[](0), new uint256[](0))
        );

        // deploy vote collection V1
        address vProxy = _deployVoteCollectionHelper(
            initializeData.xWell,
            baseStkWell,
            gProxy,
            wormholeRelayerAdapter,
            moonbeamChainId,
            proxyAdmin,
            voteCollectionOwner
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        trustedSenders[0] = WormholeTrustedSender.TrustedSender({
            chainId: baseChainId,
            addr: vProxy
        });

        /// add wormhole relayer adapter to initialize function
        initializeData.wormholeRelayer = wormholeRelayerAdapter;

        initializeMultichainGovernor(
            gProxy,
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        addresses.governorProxy = gProxy;
        addresses.governorImplementation = gImplementation;
        addresses.voteCollectionProxy = vProxy;
        addresses.wormholeRelayerAdapter = wormholeRelayerAdapter;
        addresses.proxyAdmin = proxyAdmin;
    }

    /// @notice for testing purposes only, not to be used in production as both
    /// contracts are deployed on the same chain (V2)
    function deployGovernorRelayerAndVoteCollectionV2(
        MultichainGovernor.InitializeData memory initializeData,
        bytes[] memory whitelistedCalldata,
        address proxyAdmin,
        uint16 moonbeamChainId,
        uint16 baseChainId,
        address voteCollectionOwner,
        address baseStkWell
    ) public returns (MultichainAddresses memory addresses) {
        proxyAdmin = proxyAdmin == address(0)
            ? address(new ProxyAdmin())
            : proxyAdmin;

        // deploy governor
        (
            address gProxy,
            address gImplementation
        ) = deployMockMultichainGovernor(proxyAdmin);
        address wormholeRelayerAdapter = address(
            new WormholeRelayerAdapter(new uint16[](0), new uint256[](0))
        );

        // deploy vote collection V2
        address vProxy = _deployVoteCollectionHelperV2(
            initializeData.xWell,
            baseStkWell,
            gProxy,
            wormholeRelayerAdapter,
            moonbeamChainId,
            proxyAdmin,
            voteCollectionOwner
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        trustedSenders[0] = WormholeTrustedSender.TrustedSender({
            chainId: baseChainId,
            addr: vProxy
        });

        /// add wormhole relayer adapter to initialize function
        initializeData.wormholeRelayer = wormholeRelayerAdapter;

        initializeMultichainGovernor(
            gProxy,
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );

        addresses.governorProxy = gProxy;
        addresses.governorImplementation = gImplementation;
        addresses.voteCollectionProxy = vProxy;
        addresses.wormholeRelayerAdapter = wormholeRelayerAdapter;
        addresses.proxyAdmin = proxyAdmin;
    }

    /// @notice for testing purposes only, not to be used in production
    /// THIS DEPLOYS A TEST CONTRACT THAT USES BLOCK NUMBER
    /// DO NOT USE THIS FOR DEPLOYING A PRODUCTION CONTRACT
    function deployStakedWellMock(
        address stakedToken,
        address rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address emissionManager,
        uint128 distributionDuration,
        address governance,
        address proxyAdmin
    ) public returns (address proxy, address implementation) {
        // deploy mock implementation
        implementation = deployCode(
            "deprecated/artifacts/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
        );

        // generate init calldata
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint256,uint256,address,address,uint128,address)",
            stakedToken,
            rewardToken,
            cooldownSeconds,
            unstakeWindow,
            rewardsVault,
            emissionManager,
            distributionDuration,
            governance
        );

        console.log("proxy constructor calldata mock staked well: ");
        console.logBytes(abi.encode(implementation, proxyAdmin, initData));

        // deploy proxy
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyAdmin,
                initData
            )
        );
    }

    function deployStakedWell(
        address stakedToken,
        address rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address emissionManager,
        uint128 distributionDuration,
        address governance,
        address proxyAdmin
    ) public returns (address proxy, address implementation) {
        // deploy actual stkWELL implementation for Base
        implementation = deployCode(
            "deprecated/artifacts/StakedWell.sol/StakedWell.json"
        );

        // generate init calldata
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint256,uint256,address,address,uint128,address)",
            stakedToken,
            rewardToken,
            cooldownSeconds,
            unstakeWindow,
            rewardsVault,
            emissionManager,
            distributionDuration,
            governance
        );

        console.log("proxy constructor calldata mock staked well: ");
        console.logBytes(abi.encode(implementation, proxyAdmin, initData));

        // deploy proxy
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyAdmin,
                initData
            )
        );
    }

    function deployStakedWellMoonbeam(
        address stakedToken,
        address rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address emissionManager,
        uint128 distributionDuration,
        address governance,
        address proxyAdmin
    ) public returns (address proxy, address implementation) {
        // deploy actual stkWELL implementation for Moonbeam
        implementation = deployCode(
            "deprecated/artifacts/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
        );

        // generate init calldata
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,uint256,uint256,address,address,uint128,address)",
            stakedToken,
            rewardToken,
            cooldownSeconds,
            unstakeWindow,
            rewardsVault,
            emissionManager,
            distributionDuration,
            governance
        );

        console.log("proxy constructor calldata mock staked well: ");
        console.logBytes(abi.encode(implementation, proxyAdmin, initData));

        // deploy proxy
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                proxyAdmin,
                initData
            )
        );
    }

    function deployEcosystemReserve(
        address proxyAdmin
    )
        public
        returns (
            address ecosystemReserveProxy,
            address ecosystemReserveImplementation,
            address ecosystemReserveController
        )
    {
        ecosystemReserveImplementation = deployCode(
            "deprecated/artifacts/EcosystemReserve.sol/EcosystemReserve.json"
        );

        ecosystemReserveController = deployCode(
            "deprecated/artifacts/EcosystemReserveController.sol/EcosystemReserveController.json"
        );

        ecosystemReserveProxy = address(
            new TransparentUpgradeableProxy(
                ecosystemReserveImplementation,
                proxyAdmin,
                abi.encodeWithSignature(
                    "initialize(address)",
                    ecosystemReserveController
                )
            )
        );
    }
}

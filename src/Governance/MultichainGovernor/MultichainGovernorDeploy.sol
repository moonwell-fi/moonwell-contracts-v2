pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {IStakedWell} from "@protocol/IStakedWell.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {IMultichainGovernor} from "@protocol/Governance/MultichainGovernor/IMultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";

/// Helper contract to deploy MultichainGovernor, MultichainVoteCollection,
/// Ecosystem Reserve, Ecosystem Reserve Controller and StakedWell contracts
contract MultichainGovernorDeploy is Test {
    function deployMultichainGovernor(
        address proxyAdmin
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MultichainGovernor());

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
        MultichainGovernor(governorProxy).initialize(
            initializeData,
            trustedSenders,
            whitelistedCalldata
        );
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

        proxy = address(
            new TransparentUpgradeableProxy(
                voteCollectionImpl,
                proxyAdmin,
                initData
            )
        );
    }

    // Return values as struct to avoid stack too deep error
    struct MultichainAddresses {
        address governorProxy;
        address governorImplementation;
        address voteCollectionProxy;
        address wormholeRelayerAdapter;
        address proxyAdmin;
    }

    /// @notice for testing purposes only, not to be used in production as both
    /// contracts are deployed on the same chain
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
        address wormholeRelayerAdapter = address(new WormholeRelayerAdapter());

        // deploy vote collection
        (address vProxy, ) = deployVoteCollection(
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
        implementation = deployCode("MockStakedWell.sol:MockStakedWell");

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
        implementation = deployCode("StakedWell.sol:StakedWell");

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
            "EcosystemReserve.sol:EcosystemReserve"
        );

        ecosystemReserveController = deployCode(
            "EcosystemReserveController.sol:EcosystemReserveController"
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

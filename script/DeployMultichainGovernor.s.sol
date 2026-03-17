pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MockMultichainGovernor} from "@test/mock/MockMultichainGovernor.sol";
import {MockCoreBridge, MockExecutor, MockExecutorQuoterRouter} from "@test/mock/MockCoreBridgeExecutor.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";

/// Helper contract to deploy MultichainGovernor, MultichainVoteCollection,
/// Ecosystem Reserve, Ecosystem Reserve Controller and StakedWell contracts
contract MultichainGovernorDeploy is Test {
    function deployMultichainGovernor(
        address proxyAdmin,
        address coreBridge,
        address executorAddr,
        address executorQuoterRouter
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MultichainGovernor(coreBridge, executorAddr, executorQuoterRouter));

        console.log("proxy constructor calldata: ");
        console.logBytes(abi.encode(governorImpl, proxyAdmin, ""));

        proxy = address(
            new TransparentUpgradeableProxy(governorImpl, proxyAdmin, "")
        );
    }

    function deployMockMultichainGovernor(
        address proxyAdmin,
        address coreBridge,
        address executorAddr,
        address executorQuoterRouter
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MockMultichainGovernor(coreBridge, executorAddr, executorQuoterRouter));

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

    function deployVoteCollection(
        address xWell,
        address stkWell,
        address moonbeamGovernor,
        uint16 moonbeamWormholeChainId,
        address proxyAdmin,
        address owner,
        address coreBridge,
        address executorAddr,
        address executorQuoterRouter
    ) public returns (address proxy, address voteCollectionImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint16,address)",
            xWell,
            stkWell,
            moonbeamGovernor,
            moonbeamWormholeChainId,
            owner
        );

        voteCollectionImpl = address(new MultichainVoteCollection(coreBridge, executorAddr, executorQuoterRouter));

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

    // Return values as struct to avoid stack too deep error
    struct MultichainAddresses {
        address governorProxy;
        address governorImplementation;
        address voteCollectionProxy;
        address coreBridge;
        address executor;
        address executorQuoterRouter;
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

        // Deploy mock wormhole infrastructure
        {
            MockCoreBridge _cb = new MockCoreBridge(moonbeamChainId);
            MockExecutor _ex = new MockExecutor(address(_cb));
            MockExecutorQuoterRouter _qr = new MockExecutorQuoterRouter(address(_ex));
            _ex.setSenderChainId(moonbeamChainId);
            addresses.coreBridge = address(_cb);
            addresses.executor = address(_ex);
            addresses.executorQuoterRouter = address(_qr);
        }

        // deploy governor
        (addresses.governorProxy, addresses.governorImplementation) =
            deployMockMultichainGovernor(
                proxyAdmin,
                addresses.coreBridge,
                addresses.executor,
                addresses.executorQuoterRouter
            );

        // deploy vote collection
        (addresses.voteCollectionProxy, ) = deployVoteCollection(
            initializeData.xWell,
            baseStkWell,
            addresses.governorProxy,
            moonbeamChainId,
            proxyAdmin,
            voteCollectionOwner,
            addresses.coreBridge,
            addresses.executor,
            addresses.executorQuoterRouter
        );

        {
            WormholeTrustedSender.TrustedSender[]
                memory trustedSenders = new WormholeTrustedSender.TrustedSender[](1);
            trustedSenders[0] = WormholeTrustedSender.TrustedSender({
                chainId: baseChainId,
                addr: addresses.voteCollectionProxy
            });

            initializeMultichainGovernor(
                addresses.governorProxy,
                initializeData,
                trustedSenders,
                whitelistedCalldata
            );
        }

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
        address _proxyAdmin
    ) public returns (address proxy, address implementation) {
        // deploy mock implementation (uses StakedWellMoonbeam for testing)
        // Note: Using deployCode because StakedWellMoonbeam is in Solidity 0.6.12
        implementation = deployCode(
            "artifacts/foundry/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
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
        console.logBytes(abi.encode(implementation, _proxyAdmin, initData));

        // deploy proxy
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                _proxyAdmin,
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
        address _proxyAdmin
    ) public returns (address proxy, address implementation) {
        // deploy actual stkWELL implementation for Base
        // Note: Using deployCode because StakedWell is in Solidity 0.6.12
        implementation = deployCode(
            "artifacts/foundry/StakedWell.sol/StakedWell.json"
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

        console.log("proxy constructor calldata staked well: ");
        console.logBytes(abi.encode(implementation, _proxyAdmin, initData));

        // deploy proxy
        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                _proxyAdmin,
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
        address _proxyAdmin
    ) public returns (address proxy, address implementation) {
        implementation = deployCode(
            "artifacts/foundry/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
        );

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

        console.log("proxy constructor calldata staked well moonbeam: ");
        console.logBytes(abi.encode(implementation, _proxyAdmin, initData));

        proxy = address(
            new TransparentUpgradeableProxy(
                implementation,
                _proxyAdmin,
                initData
            )
        );
    }

    function deployEcosystemReserve(
        address _proxyAdmin
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
                _proxyAdmin,
                abi.encodeWithSignature(
                    "initialize(address)",
                    ecosystemReserveController
                )
            )
        );
    }
}

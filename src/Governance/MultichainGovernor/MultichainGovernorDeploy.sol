pragma solidity 0.8.19;

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {IMultichainGovernor} from "@protocol/Governance/MultichainGovernor/IMultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import "@forge-std/Test.sol";

contract MultichainGovernorDeploy is Test {
    function deployMultichainGovernor(
        address proxyAdmin
    ) public returns (address proxy, address governorImpl) {
        governorImpl = address(new MultichainGovernor());

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
        uint16 moonbeamChainId,
        address proxyAdmin,
        address owner
    ) public returns (address proxy, address voteCollectionImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,address,uint16,address)",
            xWell,
            stkWell,
            moonbeamGovernor,
            relayer,
            moonbeamChainId,
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

    function deployGovernorRelayerAndVoteCollection(
        MultichainGovernor.InitializeData memory initializeData,
        bytes[] memory whitelistedCalldata,
        address proxyAdmin,
        uint16 moonbeamChainId,
        uint16 baseChainId,
        address voteCollectionOwner
    ) public returns (MultichainAddresses memory addresses) {
        proxyAdmin = proxyAdmin == address(0)
            ? address(new ProxyAdmin())
            : proxyAdmin;

        // deploy governor
        (address gProxy, address gImplementation) = deployMultichainGovernor(
            proxyAdmin
        );
        address wormholeRelayerAdapter = address(new WormholeRelayerAdapter());

        // deploy vote collection
        (address vProxy, ) = deployVoteCollection(
            initializeData.xWell,
            initializeData.stkWell,
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
        // deploy implementation
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
}

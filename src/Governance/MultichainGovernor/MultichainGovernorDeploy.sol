pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";

contract MultichainGovernorDeploy {
    function deployMultichainGovernor(
        MultichainGovernor.InitializeData memory initializeData,
        WormholeTrustedSender.TrustedSender[] memory trustedSenders
    ) public returns (address proxyAdmin, address proxy, address governorImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize((address,address,address,address,uint256,uint256,uint256,uint256,uint256,uint256,uint128,address,address,address),(uint16,address)[])",
            initializeData,
            trustedSenders
        );

        proxyAdmin = address(new ProxyAdmin());
        governorImpl = address(new MultichainGovernor());

        proxy = address(
            new TransparentUpgradeableProxy(governorImpl, proxyAdmin, initData)
        );
    }

    function deployVoteCollection(
        address xWell,
        address moonbeamGovernor,
        address relayer,
        uint16 moonbeamChainId,
        address proxyAdmin
    ) public returns (address proxy, address voteCollectionImpl) {
        bytes memory initData = abi.encodeWithSignature(
            "initialize(address,address,address,uint16)",
            xWell,
            moonbeamGovernor,
            relayer,
            moonbeamChainId
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

    function deployGovernorRelayerAndVoteCollection(
        MultichainGovernor.InitializeData memory initializeData,
        address proxyAdminParameter,
        uint16 moonbeamChainId
    )
        public
        returns (
            address governorProxy,
            address governorImplementation,
            address voteCollectionProxy,
            address wormholeRelayerAdapter,
            address proxyAdmin
        )
    {
        proxyAdmin = proxyAdminParameter == address(0)
            ? address(new ProxyAdmin())
            : proxyAdminParameter;

        address voteCollectionImpl = address(new MultichainVoteCollection());

        voteCollectionProxy = address(
            new TransparentUpgradeableProxy(voteCollectionImpl, proxyAdmin, "")
        );

        governorImplementation = address(new MultichainGovernor());

        governorProxy = address(
            new TransparentUpgradeableProxy(
                governorImplementation,
                proxyAdmin,
                ""
            )
        );

        WormholeTrustedSender.TrustedSender[]
            memory trustedSenders = new WormholeTrustedSender.TrustedSender[](
                1
            );

        trustedSenders[0] = WormholeTrustedSender.TrustedSender({
            chainId: moonbeamChainId,
            addr: voteCollectionProxy
        });

        wormholeRelayerAdapter = address(new WormholeRelayerAdapter());

        /// add wormhole relayer adapter to initialize function
        initializeData.wormholeRelayer = wormholeRelayerAdapter;

        MultichainGovernor(governorProxy).initialize(
            initializeData,
            trustedSenders
        );

        MultichainVoteCollection(voteCollectionProxy).initialize(
            initializeData.xWell,
            initializeData.stkWell,
            governorProxy,
            wormholeRelayerAdapter,
            moonbeamChainId
        );
    }
}

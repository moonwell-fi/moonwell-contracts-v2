pragma solidity 0.8.19;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";

contract MultichainVoteCollectionDeploy {
    function deployMultichainGovernor(address xWell, address mombeanGovernor, address relayer, address mombeanChainId, address proxyAdmin) public returns (address proxy, address voteCollectionImpl) {
        bytes memory initData = abi.encodeWithSignature(
                                                        "initialize(address, address, address, uint16)",
                                                        xWell, mombeanGovernor, relayer, mombeanChainId
        );

        voteCollectionImpl = address(new MultichainVoteCollection());

        proxy = address(
            new TransparentUpgradeableProxy(voteCollectionImpl, proxyAdmin, initData)
        );
    }
}

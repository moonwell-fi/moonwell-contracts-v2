// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {TestProposals} from "@proposals/TestProposals.sol";

import {_ADMIN_SLOT, _IMPLEMENTATION_SLOT} from "@proposals/utils/ProxyUtils.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";

contract SystemUpgradeLiveSystemBasePostProposalTest is PostProposalCheck, Configs {
    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);
    }

    function testSystemUpgradeAsTemporalGovernorSucceeds() public {
        address newProxyImplementation = address(this);

        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(addresses.getAddress("MRD_PROXY"));
        ProxyAdmin proxyAdmin = ProxyAdmin(addresses.getAddress("MRD_PROXY_ADMIN"));

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        proxyAdmin.upgrade(proxy, newProxyImplementation);

        bytes32 data = vm.load(addresses.getAddress("MRD_PROXY"), _IMPLEMENTATION_SLOT);
        assertEq(bytes32(uint256(uint160(newProxyImplementation))), data);
    }

    function testSystemProxyAdminChangeAsTemporalGovernorSucceeds() public {
        ProxyAdmin newProxyAdmin = new ProxyAdmin();

        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(addresses.getAddress("MRD_PROXY"));
        ProxyAdmin proxyAdmin = ProxyAdmin(addresses.getAddress("MRD_PROXY_ADMIN"));

        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        proxyAdmin.changeProxyAdmin(proxy, address(newProxyAdmin));

        bytes32 data = vm.load(addresses.getAddress("MRD_PROXY"), _ADMIN_SLOT);

        assertEq(newProxyAdmin.getProxyAdmin(proxy), address(newProxyAdmin));

        /// ensure that the proxy admin is set correctly
        assertEq(bytes32(uint256(uint160(address(newProxyAdmin)))), data);
    }

    function admin() public view returns (address) {
        return address(this);
    }
}

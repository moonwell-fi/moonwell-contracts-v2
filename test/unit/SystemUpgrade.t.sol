// SPDX-License-Identifier: GPL-3.0-or-later
//pragma solidity 0.8.19;
//
//import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
//import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
//
//import "@forge-std/Test.sol";
//
//import {Addresses} from "@proposals/Addresses.sol";
//import {mipb00 as mip} from "@proposals/mips/mip-b00/mip-b00.sol";
//import {TestProposals} from "@proposals/TestProposals.sol";
//
//contract SystemUpgradeUnitTest is Test {
//    bytes32 public constant _IMPLEMENTATION_SLOT =
//        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
//
//    bytes32 public constant _ADMIN_SLOT =
//        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
//
//    Addresses addresses;
//
//    function setUp() public {
//        // Run all pending proposals before doing e2e tests
//        address[] memory mips = new address[](1);
//        mips[0] = address(new mip());
//
//        TestProposals proposals = new TestProposals(mips);
//        proposals.setUp();
//        proposals.testProposals(
//            true,
//            true,
//            true,
//            true,
//            true,
//            true,
//            false,
//            true
//        );
//        addresses = proposals.addresses();
//    }
//
//    function testSystemUpgradeAsTemporalGovernorSucceeds() public {
//        address newProxyImplementation = address(this);
//
//        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
//            addresses.getAddress("MRD_PROXY")
//        );
//        ProxyAdmin proxyAdmin = ProxyAdmin(
//            addresses.getAddress("MRD_PROXY_ADMIN")
//        );
//
//        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
//        proxyAdmin.upgrade(proxy, newProxyImplementation);
//
//        bytes32 data = vm.load(
//            addresses.getAddress("MRD_PROXY"),
//            _IMPLEMENTATION_SLOT
//        );
//        assertEq(bytes32(uint256(uint160(newProxyImplementation))), data);
//    }
//
//    function testSystemProxyAdminChangeAsTemporalGovernorSucceeds() public {
//        ProxyAdmin newProxyAdmin = new ProxyAdmin();
//
//        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
//            addresses.getAddress("MRD_PROXY")
//        );
//        ProxyAdmin proxyAdmin = ProxyAdmin(
//            addresses.getAddress("MRD_PROXY_ADMIN")
//        );
//
//        assertEq(proxyAdmin.getProxyAdmin(proxy), address(proxyAdmin));
//
//        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
//        proxyAdmin.changeProxyAdmin(proxy, address(newProxyAdmin));
//
//        bytes32 data = vm.load(addresses.getAddress("MRD_PROXY"), _ADMIN_SLOT);
//
//        assertEq(newProxyAdmin.getProxyAdmin(proxy), address(newProxyAdmin));
//
//        /// ensure that the proxy admin is set correctly
//        assertEq(bytes32(uint256(uint160(address(newProxyAdmin)))), data);
//    }
//
//    function admin() public view returns (address) {
//        return address(this);
//    }
//}

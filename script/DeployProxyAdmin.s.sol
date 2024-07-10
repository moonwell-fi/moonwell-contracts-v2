// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 Utility to deploy a ProxyAdmin contract on a testnet
 to simulate:
     forge script script/DeployProxyAdmin.s.sol:DeployProxyAdminScript -vvvv --rpc-url moonbase to run:
    forge script script/DeployProxyAdmin.s.sol:DeployProxyAdminScript -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbase --verify
*/
contract DeployProxyAdminScript is Script {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();
        address proxyAdmin = address(new ProxyAdmin());
        vm.stopBroadcast();

        addresses.addAddress("MRD_PROXY_ADMIN", proxyAdmin);

        addresses.printAddresses();
    }
}

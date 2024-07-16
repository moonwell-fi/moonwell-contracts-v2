// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {ITokenSaleDistributor} from "../src/tokensale/ITokenSaleDistributor.sol";
import {ITokenSaleDistributorProxy} from "../src/tokensale/ITokenSaleDistributorProxy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract DeployTokenSale is Script {
    function run() public {
        Addresses addresses = new Addresses();

        vm.startBroadcast();

        address implementation = deployCode(
            "artifacts/foundry/TokenSaleDistributor.sol/TokenSaleDistributor.json"
        );

        address proxy = deployCode(
            "artifacts/foundry/TokenSaleDistributorProxy.sol/TokenSaleDistributorProxy.json"
        );

        ITokenSaleDistributorProxy(proxy).setPendingImplementation(
            implementation
        );

        ITokenSaleDistributor(implementation).becomeImplementation(proxy);

        vm.stopBroadcast();

        addresses.addAddress("TOKEN_SALE_DISTRIBUTOR_PROXY", address(proxy));
        addresses.addAddress(
            "TOKEN_SALE_DISTRIBUTOR_IMPL",
            address(implementation)
        );

        addresses.printAddresses();
    }
}

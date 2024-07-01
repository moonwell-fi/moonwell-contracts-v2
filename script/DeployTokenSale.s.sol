// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {ITokenSaleDistributor} from "../src/tokensale/ITokenSaleDistributor.sol";
import {ITokenSaleDistributorProxy} from "../src/tokensale/ITokenSaleDistributorProxy.sol";

contract DeployTokenSale is Script {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
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

        printAddresses();
    }

    function printAddresses() private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log(
                "        'name': '%s'\n}%s",
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}

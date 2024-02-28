// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Addresses} from "@proposals/Addresses.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import { ITokenSaleDistributor } from "../src/tokensale/ITokenSaleDistributor.sol";
import { ITokenSaleDistributorProxy } from "../src/tokensale/ITokenSaleDistributorProxy.sol";

contract DeployTokenSale is Script {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast(PRIVATE_KEY);

        address implementation = deployCode("TokenSaleDistributor.sol:TokenSaleDistributor");

        address proxy = deployCode(
            "TokenSaleDistributorProxy.sol:TokenSaleDistributorProxy"
        );

        ITokenSaleDistributorProxy(proxy).setPendingImplementation(implementation);
        
        ITokenSaleDistributor(implementation).becomeImplementation(proxy);

        vm.stopBroadcast();

        addresses.addAddress("TOKEN_SALE_DISTRIBUTOR_PROXY", address(proxy), true);
        addresses.addAddress("TOKEN_SALE_DISTRIBUTOR_IMPL", address(implementation), true);

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

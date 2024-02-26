// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

/*
 Utility to deploy a ProxyAdmin contract on a testnet
 to simulate:
     forge script script/DeployProxyAdmin.s.sol:DeployProxyAdminScript -vvvv --rpc-url moonbaseAlpha
 to run:
    forge script script/DeployProxyAdmin.s.sol:DeployProxyAdminScript -vvvv \ 
    --rpc-url moonbase/baseGoerli --broadcast --etherscan-api-key moonbaseAlpha --verify
*/
contract DeployProxyAdminScript is Script, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast(PRIVATE_KEY);
        address proxyAdmin = address(new ProxyAdmin());
        vm.stopBroadcast();

        addresses.addAddress("MOONBEAM_PROXY_ADMIN", proxyAdmin, true);

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

pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {CypherAutoLoad} from "@protocol/cypher/CypherAutoLoad.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";

contract DeployCypher is Script, Test {
    function run() public {
        Addresses addresses = new Addresses();
        vm.startBroadcast();

        CypherAutoLoad autoLoad = deployAutoLoad(addresses);

        ERC4626RateLimitedAllowance rateLimitedAllowance = deployERC4626RateLimitedAllowance(
                addresses,
                address(autoLoad)
            );

        vm.stopBroadcast();

        addresses.addAddress("CHYPHER_AUTO_LOAD", address(autoLoad));

        addresses.addAddress(
            "CYPHER_ERC4626_RATE_LIMITED_ALLOWANCE",
            address(rateLimitedAllowance)
        );

        addresses.printAddresses();
    }

    function deployAutoLoad(
        Addresses addresses
    ) public returns (CypherAutoLoad autoLoad) {
        address executor = addresses.getAddress("CYPHER_EXECUTOR");
        address beneficiary = addresses.getAddress("CYPHER_BENEFICIARY");

        autoLoad = new CypherAutoLoad(executor, beneficiary);
    }

    function deployERC4626RateLimitedAllowance(
        Addresses addresses,
        address autoLoad
    ) public returns (ERC4626RateLimitedAllowance rateLimitedAllowance) {
        rateLimitedAllowance = new ERC4626RateLimitedAllowance(
            address(addresses.getAddress("SECURITY_COUNCI")),
            autoLoad
        );
    }
}

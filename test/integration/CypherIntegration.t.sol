// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {DeployCypher} from "script/DeployCypher.s.sol";
import {CypherAutoLoad} from "@protocol/cypher/CypherAutoLoad.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";

contract CypherIntegration is Test {
    Addresses public addresses;
    CypherAutoLoad public autoLoad;
    ERC4626RateLimitedAllowance public limitedAllowance;
    MoonwellERC4626 public vault;

    function setUp() public {
        addresses = new Addresses();

        DeployCypher cypherDeployer = new DeployCypher();

        autoLoad = cypherDeployer.deployAutoLoad(addresses);

        limitedAllowance = cypherDeployer.deployERC4626RateLimitedAllowance(
            addresses,
            address(autoLoad)
        );

        vault = new MoonwellERC4626(
            ERC20(addresses.getAddress("USDC")),
            MErc20(addresses.getAddress("MOONWELL_USDC")),
            address(this),
            Comptroller(addresses.getAddress("UNITROLLER"))
        );
    }

    function testUserApproves() public {}
}

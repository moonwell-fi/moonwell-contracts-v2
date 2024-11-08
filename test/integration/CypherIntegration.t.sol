// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {DeployChyper} from "scripts/DeployChyper.s.sol";
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
        Addresses addresses = new Addresses();

        DeployCypher cypherDeployer = new DeployChyper();

        CypherAutoLoad autoLoad = cypherDeployer.autoLoad(addresses);

        limitedAllowance = new ERC4626RateLimitedAllowance(addresses);

        vault = new MoonwellERC4626(
            ERC20(addresses.getAddress("USDC")),
            MErc20(addresses.getAddress("MOONWELL_USDC")),
            address(this),
            Comptroller(addresses.getAddress("UNITROLLER"))
        );
    }

    function testUserApproves();
}

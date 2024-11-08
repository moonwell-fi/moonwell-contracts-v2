// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {DeployCypher} from "script/DeployCypher.s.sol";
import {CypherAutoLoad} from "@protocol/cypher/CypherAutoLoad.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";

contract CypherIntegrationTest is Test {
    using SafeCast for *;

    Addresses public addresses;
    CypherAutoLoad public autoLoad;
    ERC4626RateLimitedAllowance public limitedAllowance;
    MoonwellERC4626 public vault;
    ERC20 public underlying;

    address public beneficiary;
    address public executor;

    function setUp() public {
        addresses = new Addresses();

        DeployCypher cypherDeployer = new DeployCypher();

        autoLoad = cypherDeployer.deployAutoLoad(addresses);

        limitedAllowance = cypherDeployer.deployERC4626RateLimitedAllowance(
            addresses,
            address(autoLoad)
        );

        underlying = ERC20(addresses.getAddress("USDC"));

        vault = new MoonwellERC4626(
            underlying,
            MErc20(addresses.getAddress("MOONWELL_USDC")),
            address(this),
            Comptroller(addresses.getAddress("UNITROLLER"))
        );

        beneficiary = addresses.getAddress("CYPHER_BENEFICIARY");
        executor = addresses.getAddress("CYPHER_EXECUTOR");
    }

    function testFuzzExecutorCanTransfer(
        uint128 bufferCap,
        uint128 rateLimitPerSecond,
        uint256 underlyingAmount
    ) public {
        bufferCap = _bound(
            bufferCap,
            1.toUint128(),
            (type(uint128).max).toUint128()
        ).toUint128();
        rateLimitPerSecond = _bound(
            rateLimitPerSecond,
            1.toUint128(),
            type(uint128).max.toUint128()
        ).toUint128();
        underlyingAmount = _bound(underlyingAmount, 1, bufferCap);

        deal(address(underlying), address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        vault.approve(address(limitedAllowance), type(uint256).max);

        limitedAllowance.approve(address(vault), rateLimitPerSecond, bufferCap);

        uint256 receiverBalanceBefore = underlying.balanceOf(beneficiary);

        vm.prank(executor);
        autoLoad.debit(
            address(limitedAllowance),
            address(vault),
            address(this),
            underlyingAmount
        );

        assertEq(
            receiverBalanceBefore + underlyingAmount,
            underlying.balanceOf(beneficiary),
            "Wrong receiver balance after withdrawn"
        );
    }
}

// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC4626} from "solmate/test/utils/mocks/MockERC4626.sol";

import {Address} from "@utils/Address.sol";
import {CypherAutoLoad} from "@protocol/cypher/CypherAutoLoad.sol";
import {IRateLimitedAllowance} from "@protocol/cypher/IRateLimitedAllowance.sol";
import {ERC4626RateLimitedAllowance} from "@protocol/cypher/ERC4626RateLimitedAllowance.sol";

contract CypherAutoLoadUnitTest is Test {
    using SafeCast for *;
    event Withdraw(
        address indexed token,
        address indexed user,
        address indexed beneficiary,
        uint amount
    );

    MockERC20 underlying;
    MockERC4626 public vault;
    CypherAutoLoad public autoLoad;
    IRateLimitedAllowance public rateLimitedAllowance;

    address beneficiary = address(0xABCD);
    address executor = address(0xBEEF);

    function setUp() public {
        autoLoad = new CypherAutoLoad(executor, beneficiary);

        rateLimitedAllowance = IRateLimitedAllowance(
            address(
                new ERC4626RateLimitedAllowance(
                    address(this),
                    address(autoLoad)
                )
            )
        );

        autoLoad.setRateLimitedAllowance(rateLimitedAllowance);

        underlying = new MockERC20("Mock Token", "TKN", 18);
        vault = new MockERC4626(underlying, "Vault Mock", "VAULT");
    }

    function testFuzzSpenderCanTransfer(
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

        underlying.mint(address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);

        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        uint256 beneficiaryBalanceBefore = underlying.balanceOf(beneficiary);

        vm.prank(executor);
        autoLoad.debit(address(vault), address(this), underlyingAmount);

        assertEq(
            beneficiaryBalanceBefore + underlyingAmount,
            underlying.balanceOf(beneficiary),
            "Wrong beneficiary balance after withdrawn"
        );
    }
}

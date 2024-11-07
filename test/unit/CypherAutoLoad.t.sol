// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";
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
    event BeneficiaryChanged(address _beneficiary);

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

        underlying = new MockERC20("Mock Token", "TKN", 18);
        vault = new MockERC4626(underlying, "Vault Mock", "VAULT");
    }

    function testFuzzExecutorCanCallDebit(
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
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(vault),
            address(this),
            underlyingAmount
        );

        assertEq(
            beneficiaryBalanceBefore + underlyingAmount,
            underlying.balanceOf(beneficiary),
            "Wrong beneficiary balance after withdrawn"
        );
    }

    function testDebitEmitWithdrawEvent() public {
        uint128 rateLimitPerSecond = 1.5e16.toUint128();
        uint128 bufferCap = 1000e18.toUint128();
        uint256 underlyingAmount = 100e18;

        underlying.mint(address(this), underlyingAmount);
        underlying.approve(address(vault), underlyingAmount);
        vault.deposit(underlyingAmount, address(this));

        vault.approve(address(rateLimitedAllowance), type(uint256).max);
        rateLimitedAllowance.approve(
            address(vault),
            rateLimitPerSecond,
            bufferCap
        );

        vm.prank(executor);
        vm.expectEmit();
        emit Withdraw(
            address(vault),
            address(this),
            address(beneficiary),
            underlyingAmount
        );
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(vault),
            address(this),
            underlyingAmount
        );
    }

    function testOnlyExecutorCanCallDebit() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(this)),
                " is missing role ",
                Strings.toHexString(uint256(autoLoad.EXECUTIONER_ROLE()), 32)
            )
        );
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(vault),
            address(this),
            1
        );
    }

    function testDebitRevertIfUserAdressIsZero() public {
        vm.prank(executor);
        vm.expectRevert("Invalid user address");
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(vault),
            address(0),
            1
        );
    }

    function testDebitRevertIfTokenAdressIsZero() public {
        vm.prank(executor);
        vm.expectRevert("Invalid token address");
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(0),
            address(this),
            1
        );
    }

    function testAdminCanPause() public {
        autoLoad.pause();

        vm.assertEq(autoLoad.paused(), true);
    }

    function testExecutorCanPause() public {
        vm.prank(executor);
        autoLoad.pause();

        vm.assertEq(autoLoad.paused(), true);
    }

    function testAdminCanUnpause() public {
        testAdminCanPause();

        autoLoad.unpause();
        vm.assertEq(autoLoad.paused(), false);
    }

    function testRevertIfUnpauseWhenNotPaused() public {
        vm.expectRevert("Pausable: not paused");
        autoLoad.unpause();
    }

    function testRevertIfPauseWhenPaused() public {
        testAdminCanPause();

        vm.expectRevert("Pausable: paused");
        autoLoad.pause();
    }

    function testOnlyAdminCanPause() public {
        vm.prank(address(0x1234));
        vm.expectRevert("AccessControl: sender does not have permission");
        autoLoad.pause();
    }

    function testOnlyAdminCanUnpause() public {
        testAdminCanPause();

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(0x1234)),
                " is missing role ",
                Strings.toHexString(uint256(autoLoad.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        vm.prank(address(0x1234));
        autoLoad.unpause();
    }

    function testDebitRevertsIfPaused() public {
        testAdminCanPause();

        vm.prank(executor);
        vm.expectRevert("Pausable: paused");
        autoLoad.debit(
            address(rateLimitedAllowance),
            address(vault),
            address(this),
            1
        );
    }

    function testOwnerCanSetBeneficiary() public {
        vm.expectEmit();
        emit BeneficiaryChanged(address(0xCAFE));
        autoLoad.setBeneficiary(address(0xCAFE));
    }

    function testOnlyAdminCanSetBeneficiary() public {
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                Strings.toHexString(address(0xCAFE)),
                " is missing role ",
                Strings.toHexString(uint256(autoLoad.DEFAULT_ADMIN_ROLE()), 32)
            )
        );
        vm.prank(address(0xCAFE));
        autoLoad.setBeneficiary(address(0xCAFE));
    }
}

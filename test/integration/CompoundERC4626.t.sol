// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {mip01 as mip} from "@test/proposals/mips/mip01.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Compound4626Deploy} from "@protocol/4626/4626Deploy.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract CompoundERC4626LiveSystemBaseTest is Test, Compound4626Deploy {
    address constant rewardRecipient = address(10_000_000);
    Addresses addresses;
    TestProposals proposals;

    IComptroller public comptroller;
    ERC20 public usdc;
    ERC20 public underlying;
    ERC20 public well;

    CompoundERC4626 public vault;

    function setUp() public {
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        proposals = new TestProposals(mips);
        proposals.setUp();
        proposals.testProposals(
            true,
            true,
            false,
            false,
            true,
            true,
            false,
            true
        ); /// only setup after deploy, build, and run, do not validate
        addresses = proposals.addresses();
        comptroller = IComptroller(addresses.getAddress("UNITROLLER"));
        usdc = ERC20(addresses.getAddress("USDC"));
        well = ERC20(addresses.getAddress("WELL"));
        underlying = usdc;

        addresses.addAddress("REWARDS_RECEIVER", rewardRecipient);
        deployVaults(addresses, rewardRecipient);

        vault = CompoundERC4626(addresses.getAddress("USDC_VAULT"));
    }

    function testSetup() public {
        assertEq(address(vault.asset()), address(underlying));
        assertEq(address(vault.well()), addresses.getAddress("WELL"));
        assertEq(
            address(vault.mToken()),
            addresses.getAddress("MOONWELL_USDC")
        );
        assertEq(
            address(vault.comptroller()),
            addresses.getAddress("UNITROLLER")
        );
        assertEq(vault.rewardRecipient(), rewardRecipient);

        console.log("name: ", vault.name());
        console.log("symbol: ", vault.symbol());
    }

    function testFailDepositWithNotEnoughApproval() public {
        deal(address(underlying), address(this), 0.5e18);
        underlying.approve(address(vault), 0.5e18);
        assertEq(underlying.allowance(address(this), address(vault)), 0.5e18);

        vault.deposit(1e18, address(this));
    }

    function testFailWithdrawWithNotEnoughUnderlyingAmount() public {
        deal(address(underlying), address(this), 0.5e18);
        underlying.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNotEnoughShareAmount() public {
        deal(address(underlying), address(this), 0.5e18);
        underlying.approve(address(vault), 0.5e18);

        vault.deposit(0.5e18, address(this));

        vault.redeem(1e18, address(this), address(this));
    }

    function testSucceedRedeemWithCorrectShareAmount() public {
        uint256 mintAmount = 1_000_000e6;
        deal(address(underlying), address(this), mintAmount);
        underlying.approve(address(vault), mintAmount);

        vault.deposit(mintAmount, address(this));

        vault.redeem(mintAmount, address(this), address(this));

        assertApproxEqRel(
            underlying.balanceOf(address(this)),
            mintAmount,
            0.0000001e18, /// small rounding down in protocol's favor and no interest accrued
            "underlying balance"
        );
    }

    function testRewardsAccrueAndSentToRecipient() public {
        uint256 mintAmount = 10_000_000e6;

        deal(address(underlying), address(this), mintAmount);
        deal(address(well), addresses.getAddress("MRD_PROXY"), 10_000_000e18);

        underlying.approve(address(vault), mintAmount);

        assertEq(well.balanceOf(rewardRecipient), 0);

        vault.deposit(mintAmount, address(this));
        vm.warp(block.timestamp + 1 weeks);

        vault.claimRewards();
        assertGt(well.balanceOf(rewardRecipient), 0);
    }

    function testMaxMint() public {
        uint256 maxMint = vault.maxMint(address(this));
        uint256 borrowCap = comptroller.borrowCaps(
            addresses.getAddress("MOONWELL_USDC")
        );

        assertGt(maxMint, 0);
        assertGt(maxMint, 10_000_000e6);
        assertLt(maxMint, borrowCap);
    }

    function testFailWithdrawWithNoUnderlyingAmount() public {
        vault.withdraw(1e18, address(this), address(this));
    }

    function testFailRedeemWithNoShareAmount() public {
        vault.redeem(1e18, address(this), address(this));
    }

    function testFailDepositWithNoApproval() public {
        vault.deposit(1e18, address(this));
    }

    function testFailMintWithNoApproval() public {
        vault.mint(1e18, address(this));
    }

    function testFailDepositZero() public {
        vault.deposit(0, address(this));
    }

    function testMintZero() public {
        vault.mint(0, address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(address(this))), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function testFailRedeemZero() public {
        vault.redeem(0, address(this), address(this));
    }

    function testWithdrawZero() public {
        vault.withdraw(0, address(this), address(this));

        assertEq(vault.balanceOf(address(this)), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(address(this))), 0);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_claimRewards() public {
        vault.claimRewards();
    }
}

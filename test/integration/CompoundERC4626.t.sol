// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {LibCompound} from "@protocol/4626/LibCompound.sol";
import {mipb01 as mip} from "@test/proposals/mips/mip-b01/mip-b01.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Compound4626Deploy} from "@protocol/4626/4626Deploy.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract CompoundERC4626LiveSystemBaseTest is Test, Compound4626Deploy {
    using LibCompound for MErc20;
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
            false,
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
        assertEq(
            address(vault.mToken()),
            addresses.getAddress("MOONWELL_USDC")
        );
        assertEq(
            address(vault.comptroller()),
            addresses.getAddress("UNITROLLER")
        );
        assertEq(vault.rewardRecipient(), rewardRecipient);

        assertEq(vault.name(), "ERC4626-Wrapped Moonwell USDbC");
        assertEq(vault.symbol(), "wmUSDbC");
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

    function testMintSucceedRedeemWithCorrectShareAmount() public {
        uint256 mintAmount = vault.maxDeposit(address(0));

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

    function testWithdrawWithZeroCashFails() public {
        testMaxMintDepositSucceedsMaxMintZero();
        deal(address(underlying), addresses.getAddress("MOONWELL_USDC"), 0);

        uint256 withdrawAmount = vault.balanceOf(address(this));

        vm.expectRevert(
            abi.encodeWithSignature(
                "CompoundERC4626__CompoundError(uint256)",
                9
            )
        );
        vault.withdraw(withdrawAmount, address(this), address(this));
    }

    function testRewardAmountEqZeroClaimRewards() public {
        testRewardsAccrueAndSentToRecipient();

        uint256 rewardBalance = well.balanceOf(rewardRecipient);
        vault.claimRewards();

        assertEq(rewardBalance, well.balanceOf(rewardRecipient));
    }

    function testSweepFailsNotRewardRecipient() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);

        vm.expectRevert("CompoundERC4626: forbidden");
        vault.sweepRewards(tokens);
    }

    function testSweepFailsMToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = addresses.getAddress("MOONWELL_USDC");

        vm.expectRevert("CompoundERC4626: cannot sweep mToken");
        vm.prank(rewardRecipient);
        vault.sweepRewards(tokens);
    }

    function testSweepSucceedsAsRewardRecipient() public {
        uint256 mintAmount = 100e6;
        deal(address(underlying), address(vault), mintAmount);

        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);

        vm.prank(rewardRecipient);
        vault.sweepRewards(tokens);
        assertEq(usdc.balanceOf(vault.rewardRecipient()), mintAmount);
    }

    function testMintGuardianPausedMaxMintReturnsZero() public {
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMintPaused(
            MToken(addresses.getAddress("MOONWELL_USDC")),
            true
        );
        vm.stopPrank();

        assertEq(vault.maxMint(address(this)), 0);
    }

    function testSetMarketSupplyCaps() public {
        uint256[] memory supplyCaps = new uint256[](1);
        supplyCaps[0] = 0;

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = MToken(addresses.getAddress("MOONWELL_USDC"));

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMarketSupplyCaps(mTokens, supplyCaps);

        assertEq(vault.maxMint(address(0)), type(uint256).max);
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

    function testMaxMintDepositSucceedsMaxMintZero() public {
        uint256 maxMint = vault.maxMint(address(this));
        uint256 borrowCap = comptroller.borrowCaps(
            addresses.getAddress("MOONWELL_USDC")
        );

        assertGt(maxMint, 0);
        assertGt(maxMint, 10_000_000e6);
        assertLt(maxMint, borrowCap);

        deal(address(underlying), address(this), maxMint);

        underlying.approve(address(vault), maxMint);
        vault.deposit(maxMint, address(this));

        assertEq(vault.maxMint(address(this)), 0); /// nothing left to mint
        assertApproxEqRel(
            vault.maxWithdraw(address(this)),
            maxMint,
            0.0000001e18
        );
    }

    function testMaxRedeem() public {
        testMaxMintDepositSucceedsMaxMintZero();

        uint256 maxRedeem = vault.maxRedeem(address(this));
        assertEq(maxRedeem, vault.balanceOf(address(this)));
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

    function testInflationAttack() public {
        address alice = address(0x1);
        address bob = address(0x2);

        //set supply cap to unlimited
        uint256[] memory supplyCaps = new uint256[](1);
        supplyCaps[0] = 0;

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = MToken(addresses.getAddress("MOONWELL_USDC"));

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMarketSupplyCaps(mTokens, supplyCaps);
        vm.stopPrank();

        uint256 mintAmount = 1_000_000e18;
        uint256 aliceInitialMintAmount = 1;
        uint256 aliceDonationAmount = 10000e18 - 1;
        uint256 bobAmount = 19999e18;

        //underlying asset transfers
        deal(address(underlying), address(this), mintAmount);
        deal(address(underlying), alice, aliceInitialMintAmount);
        deal(address(underlying), bob, bobAmount);

        //attacker alice - deposit and donate
        vm.startPrank(alice);

        underlying.approve(address(vault), aliceInitialMintAmount);
        vault.deposit(aliceInitialMintAmount, alice);
        vault.balanceOf(alice);
        // alice balance - initial deposit - 1

        deal(address(vault.mToken()), alice, aliceDonationAmount);
        vault.mToken().transfer(address(vault), aliceDonationAmount);

        vm.stopPrank();

        //victim bob - deposit
        vm.startPrank(bob);
        underlying.approve(address(vault), bobAmount);
        vault.deposit(bobAmount, address(this));
        assertEq(vault.balanceOf(bob), 0);
        // 0 balance
        vm.stopPrank();

        //alice redeems
        vm.startPrank(alice);
        vault.redeem(aliceInitialMintAmount, alice, alice);
        vm.stopPrank();
    }
}

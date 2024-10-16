// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MockERC20} from "@test/mock/MockERC20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {LibCompound} from "@protocol/4626/LibCompound.sol";
import {Factory4626} from "@protocol/4626/Factory4626.sol";
import {deployFactory} from "@protocol/4626/4626FactoryDeploy.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ERC4626LiveIntegrationTest is Test {
    using LibCompound for MErc20;
    address constant rewardRecipient = address(10_000_000);

    ERC20 public underlying;
    ERC20 public well;

    MToken mToken;

    MoonwellERC4626 public vault;
    Comptroller comptroller;
    MarketBase public marketBase;

    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);

        addresses.addAddressEOA("REWARDS_RECEIVER", rewardRecipient);
        Factory4626 factory = deployFactory(addresses);

        mToken = MToken(addresses.getAddress("MOONWELL_USDBC"));
        underlying = ERC20(addresses.getAddress("USDBC"));

        uint256 mintAmount = 10 ** 4;

        deal(address(underlying), address(this), mintAmount);
        underlying.approve(address(factory), mintAmount);

        if (
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_USDBC"))
            ) > 10 ** ((underlying.decimals() * 2) / 3)
        ) {
            vault = MoonwellERC4626(
                factory.deployMoonwellERC4626(address(mToken), rewardRecipient)
            );
        } else if (
            marketBase.getMaxSupplyAmount(
                MToken(addresses.getAddress("MOONWELL_USDC"))
            ) > 10 ** ((ERC20(addresses.getAddress("USDC")).decimals() * 2) / 3)
        ) {
            mToken = MToken(addresses.getAddress("MOONWELL_USDC"));
            underlying = ERC20(addresses.getAddress("USDC"));
            deal(address(underlying), address(this), mintAmount);
            underlying.approve(address(factory), mintAmount);

            vault = MoonwellERC4626(
                factory.deployMoonwellERC4626(address(mToken), rewardRecipient)
            );
        } else {
            // if supply cap has been reached, skip the test
            vm.skip(true);
        }

        well = ERC20(addresses.getAddress("GOVTOKEN"));
    }

    function testSetup() public view {
        assertEq(address(vault.asset()), address(underlying));
        assertEq(address(vault.mToken()), address(mToken));
        assertEq(
            address(vault.comptroller()),
            addresses.getAddress("UNITROLLER")
        );
        assertEq(vault.rewardRecipient(), rewardRecipient);

        string memory vaultName = string.concat(
            "ERC4626-Wrapped Moonwell ",
            underlying.symbol()
        );
        assertEq(vault.name(), vaultName);

        string memory vaultSymbol = string.concat("wm", underlying.symbol());

        assertEq(vault.symbol(), vaultSymbol);
        assertEq(vault.totalSupply(), 10 ** 4, "total supply incorrect");
        assertGt(
            mToken.balanceOf(address(vault)),
            40e6,
            "underlying mToken balance incorrect"
        );
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
        uint256 mintAmount = 1_000e6;

        deal(address(underlying), address(this), mintAmount);
        underlying.approve(address(vault), mintAmount);

        vault.deposit(mintAmount, address(this));
        vault.redeem(mintAmount, address(this), address(this));

        assertGt(
            mintAmount,
            underlying.balanceOf(address(this)),
            "did not round down on atomic deposit and withdrawal"
        );
    }

    function testMintSucceedRedeemWithCorrectShareAmount() public {
        uint256 mintAmount = vault.maxDeposit(address(0));

        deal(address(underlying), address(this), mintAmount);
        underlying.approve(address(vault), mintAmount);

        vault.deposit(mintAmount, address(this));

        vault.redeem(mintAmount, address(this), address(this));

        /// small rounding down in protocol's favor and no interest accrued
        /// so the balance should slightly decrease after round-tripping
        assertGt(
            mintAmount,
            underlying.balanceOf(address(this)),
            "underlying balance did not decrease"
        );
    }

    function testWithdrawWithZeroCashFails() public {
        testMaxMintDepositSucceedsMaxMintGtZero();
        deal(address(underlying), address(mToken), 0);

        uint256 withdrawAmount = vault.balanceOf(address(this));

        vm.expectRevert(
            abi.encodeWithSignature(
                "CompoundERC4626__CompoundError(uint256)",
                9
            )
        );
        vault.withdraw(withdrawAmount, address(this), address(this));
    }

    function testSweepFailsNotRewardRecipient() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(underlying);

        vm.expectRevert("CompoundERC4626: forbidden");
        vault.sweepRewards(tokens);
    }

    function testSweepFailsMToken() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(mToken);

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
        assertEq(underlying.balanceOf(vault.rewardRecipient()), mintAmount);
    }

    function testMintGuardianPausedMaxMintReturnsZero() public {
        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMintPaused(mToken, true);
        vm.stopPrank();

        assertEq(vault.maxMint(address(this)), 0);
    }

    function testSetMarketSupplyCaps() public {
        uint256[] memory supplyCaps = new uint256[](1);
        supplyCaps[0] = 0;

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = mToken;

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMarketSupplyCaps(mTokens, supplyCaps);

        assertEq(vault.maxMint(address(0)), type(uint256).max);
    }

    function testMaxMint() public view {
        uint256 maxMint = vault.maxMint(address(this));
        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        assertGt(maxMint, 0);
        assertLt(maxMint, supplyCap);
    }

    function testMaxMintDepositSucceedsMaxMintGtZero() public {
        assertEq(
            MErc20(address(mToken)).accrueInterest(),
            0,
            "accrue interest failed"
        );

        uint256 maxMint = vault.maxMint(address(this));
        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        assertGt(maxMint, 0, "max mint not gt 0");
        assertLt(maxMint, supplyCap, "max mint not lt supply cap");

        uint256 depositAmount = vault.maxDeposit(address(0));
        deal(address(underlying), address(this), depositAmount);

        underlying.approve(address(vault), depositAmount);
        vault.mint(maxMint, address(this));

        assertEq(
            vault.maxMint(address(this)),
            0,
            "should be nothing left to mint"
        );
        assertGt(
            depositAmount,
            vault.maxWithdraw(address(this)),
            "withdraw amount should be lt deposit amount"
        );
    }

    function testMaxRedeem() public {
        testMaxMintDepositSucceedsMaxMintGtZero();

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
        uint256 startingBalance = vault.balanceOf(address(this));
        uint256 startingAssets = vault.convertToAssets(startingBalance);

        vault.mint(0, address(this));

        assertEq(
            startingBalance - vault.balanceOf(address(this)),
            0,
            "balance should remain unchanged"
        );
        assertEq(
            startingAssets -
                vault.convertToAssets(vault.balanceOf(address(this))),
            0,
            "assets should remain unchanged"
        );
    }

    function testFailRedeemZero() public {
        vault.redeem(0, address(this), address(this));
    }

    function testWithdrawZero() public {
        uint256 startingBalance = vault.balanceOf(address(this));
        uint256 startingAssets = vault.convertToAssets(startingBalance);

        vault.withdraw(0, address(this), address(this));

        assertEq(
            startingBalance - vault.balanceOf(address(this)),
            0,
            "balance should remain unchanged"
        );
        assertEq(
            startingAssets -
                vault.convertToAssets(vault.balanceOf(address(this))),
            0,
            "assets should remain unchanged"
        );
    }

    function testClaimRewards() public {
        vault.claimRewards();
    }

    function testInflationAttack() public {
        address alice = address(0x1);
        address bob = address(0x2);

        //set supply cap to unlimited
        uint256[] memory supplyCaps = new uint256[](1);
        supplyCaps[0] = 0;

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = mToken;

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

    function testConvertToShareThenAssetsRoundsDown(
        uint256 assets
    ) public view {
        assets = _bound(assets, 1, 100_000_000 * 1e18);

        uint256 shares = vault.convertToShares(assets);
        uint256 assets2 = vault.convertToAssets(shares);

        assertGe(assets, assets2, "initial assets should be gte assets2");
    }

    function testConvertFromSharesToAssetsRoundsDown(
        uint256 shares
    ) public view {
        shares = _bound(shares, 1, 1_000_000 * 1e18);

        uint256 assets = vault.convertToAssets(shares);
        uint256 shares2 = vault.convertToShares(assets);

        assertGe(shares, shares2, "initial shares should be gte shares2");
    }
}

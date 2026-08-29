// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {TokenErrorReporter} from "@protocol/TokenErrorReporter.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {WhitePaperInterestRateModel} from "@protocol/irm/WhitePaperInterestRateModel.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @notice Covers the cash accounting `MErc20` keeps in `internalCash`: what credits and
///         debits it, that underlying donated straight to the market never touches it, and
///         the `sweepTokenAndSync` admin entry point that reconciles it with the balance
///         the market actually holds.
contract MErc20InternalCashUnitTest is Test, TokenErrorReporter {
    /// @dev slot of `MTokenStorage.internalCash`, confirmed by
    ///      `forge inspect MErc20Delegate storageLayout`
    uint256 internal constant INTERNAL_CASH_SLOT = 20;

    /// @dev slot of `MTokenStorage.internalCashInitialized`
    uint256 internal constant INTERNAL_CASH_INITIALIZED_SLOT = 21;

    /// @notice mirrors `MErc20Interface.CashSynced`
    event CashSynced(uint oldInternalCash, uint newInternalCash);

    /// @notice mirrors `MErc20Interface.UnderlyingSwept`
    event UnderlyingSwept(address indexed recipient, uint amount);

    Comptroller public comptroller;
    SimplePriceOracle public oracle;
    FaucetTokenWithPermit public token;
    InterestRateModel public irModel;
    MErc20Delegate public implementation;
    MErc20Delegator public mToken;

    /// @notice a second market, so a borrower can post collateral without that collateral
    ///         also being the cash they are trying to borrow
    FaucetTokenWithPermit public collateralToken;
    MErc20Delegator public mCollateral;

    address public constant supplier = address(0x51);
    address public constant borrower = address(0xB0);
    address public constant donor = address(0xD0);

    uint256 public constant supplyAmount = 100e18;
    uint256 public constant donationAmount = 10e18;

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        token = new FaucetTokenWithPermit(0, "Testing", 18, "TEST");
        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);
        implementation = new MErc20Delegate();

        mToken = new MErc20Delegator(
            address(token),
            comptroller,
            irModel,
            1e18, /// 1:1 exchange rate keeps the arithmetic in these tests readable
            "Test mToken",
            "mTEST",
            8,
            payable(address(this)),
            address(implementation),
            ""
        );

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(this),
            abi.encodeWithSignature(
                "initialize(address,address)",
                address(comptroller),
                address(this)
            )
        );
        distributor = MultiRewardDistributor(address(proxy));

        collateralToken = new FaucetTokenWithPermit(
            0,
            "Collateral",
            18,
            "COLL"
        );
        mCollateral = new MErc20Delegator(
            address(collateralToken),
            comptroller,
            irModel,
            1e18,
            "Test collateral mToken",
            "mCOLL",
            8,
            payable(address(this)),
            address(implementation),
            ""
        );

        comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);

        comptroller._supportMarket(MToken(address(mToken)));
        oracle.setUnderlyingPrice(MToken(address(mToken)), 1e18);
        comptroller._setCollateralFactor(MToken(address(mToken)), 0.8e18);

        comptroller._supportMarket(MToken(address(mCollateral)));
        oracle.setUnderlyingPrice(MToken(address(mCollateral)), 1e18);
        comptroller._setCollateralFactor(MToken(address(mCollateral)), 0.8e18);
    }

    /// ---------------------------------------------------------------------------
    /// cash tracking
    /// ---------------------------------------------------------------------------

    function testSetupMarksCashTrackingInitialized() public view {
        assertTrue(
            mToken.internalCashInitialized(),
            "constructor did not initialize cash tracking"
        );
        assertEq(mToken.internalCash(), 0, "fresh market holds cash");
        assertEq(mToken.getCash(), 0, "getCash does not read internalCash");
    }

    function testMintCreditsInternalCash() public {
        _mint(supplier, supplyAmount);

        assertEq(mToken.internalCash(), supplyAmount, "internalCash");
        assertEq(mToken.getCash(), supplyAmount, "getCash");
        assertEq(
            token.balanceOf(address(mToken)),
            supplyAmount,
            "underlying balance"
        );
    }

    function testRedeemDebitsInternalCash() public {
        _mint(supplier, supplyAmount);

        uint256 redeemAmount = supplyAmount / 4;

        vm.prank(supplier);
        assertEq(
            mToken.redeemUnderlying(redeemAmount),
            uint(Error.NO_ERROR),
            "redeem failed"
        );

        assertEq(
            mToken.internalCash(),
            supplyAmount - redeemAmount,
            "internalCash"
        );
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
    }

    function testBorrowAndRepayMoveInternalCash() public {
        _mint(supplier, supplyAmount);

        uint256 borrowAmount = supplyAmount / 4;
        _borrow(supplier, borrowAmount);

        assertEq(
            mToken.internalCash(),
            supplyAmount - borrowAmount,
            "internalCash after borrow"
        );

        token.allocateTo(supplier, borrowAmount);

        vm.startPrank(supplier);
        token.approve(address(mToken), borrowAmount);
        assertEq(
            mToken.repayBorrow(borrowAmount),
            uint(Error.NO_ERROR),
            "repay failed"
        );
        vm.stopPrank();

        assertEq(
            mToken.internalCash(),
            supplyAmount,
            "internalCash after repay"
        );
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
    }

    function testAddAndReduceReservesMoveInternalCash() public {
        _mint(supplier, supplyAmount);

        uint256 reserveAmount = 5e18;

        token.allocateTo(address(this), reserveAmount);
        token.approve(address(mToken), reserveAmount);
        assertEq(
            mToken._addReserves(reserveAmount),
            uint(Error.NO_ERROR),
            "add reserves failed"
        );

        assertEq(
            mToken.internalCash(),
            supplyAmount + reserveAmount,
            "internalCash after add reserves"
        );

        assertEq(
            mToken._reduceReserves(reserveAmount),
            uint(Error.NO_ERROR),
            "reduce reserves failed"
        );

        assertEq(
            mToken.internalCash(),
            supplyAmount,
            "internalCash after reduce reserves"
        );
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
    }

    /// ---------------------------------------------------------------------------
    /// donations
    /// ---------------------------------------------------------------------------

    function testDonationDoesNotMoveCashOrExchangeRate() public {
        _mint(supplier, supplyAmount);

        uint256 exchangeRateBefore = mToken.exchangeRateStored();

        _donate(donationAmount);

        assertEq(
            token.balanceOf(address(mToken)),
            supplyAmount + donationAmount,
            "donation did not land"
        );
        assertEq(mToken.internalCash(), supplyAmount, "internalCash moved");
        assertEq(mToken.getCash(), supplyAmount, "getCash moved");
        assertEq(
            mToken.exchangeRateStored(),
            exchangeRateBefore,
            "exchange rate moved"
        );
    }

    /// @notice the donated underlying is not lendable, so a donation cannot be used to
    ///         push borrows past what suppliers actually funded. The borrower posts
    ///         collateral in a second market, so the only thing that can stop the borrow
    ///         is the cash check
    function testDonationIsNotBorrowable() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);
        _supplyCollateral(borrower, supplyAmount * 10);

        address[] memory markets = new address[](1);
        markets[0] = address(mToken);

        vm.startPrank(borrower);
        comptroller.enterMarkets(markets);

        assertEq(
            mToken.borrow(supplyAmount + 1),
            uint(Error.TOKEN_INSUFFICIENT_CASH),
            "donation was lent out"
        );

        assertEq(
            mToken.borrow(supplyAmount),
            uint(Error.NO_ERROR),
            "borrow within internalCash failed"
        );
        vm.stopPrank();

        assertEq(mToken.internalCash(), 0, "internalCash");
        assertEq(
            token.balanceOf(address(mToken)),
            donationAmount,
            "donation did not stay behind"
        );
    }

    /// @notice a donation is stranded until the admin sweeps or syncs it: redeeming every
    ///         mToken in existence leaves it sitting in the market
    function testDonationIsNotRedeemable() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);

        uint256 supplierTokens = mToken.balanceOf(supplier);

        vm.prank(supplier);
        assertEq(
            mToken.redeem(supplierTokens),
            uint(Error.NO_ERROR),
            "redeem failed"
        );

        assertEq(mToken.totalSupply(), 0, "mTokens outstanding");
        assertEq(mToken.internalCash(), 0, "internalCash");
        assertEq(
            token.balanceOf(address(mToken)),
            donationAmount,
            "donation did not stay behind"
        );
        assertEq(
            token.balanceOf(supplier),
            supplyAmount,
            "supplier took the donation"
        );
    }

    /// ---------------------------------------------------------------------------
    /// sweepTokenAndSync
    /// ---------------------------------------------------------------------------

    function testSweepRevertsForNonAdmin() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);

        vm.prank(supplier);
        vm.expectRevert(
            "MErc20::sweepTokenAndSync: only admin can sweep tokens"
        );
        mToken.sweepTokenAndSync(donationAmount);
    }

    function testSweepRevertsAboveSurplus() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);

        vm.expectRevert("MErc20::sweepTokenAndSync: amount exceeds surplus");
        mToken.sweepTokenAndSync(donationAmount + 1);
    }

    /// @notice with no donation there is no surplus, so any non zero sweep is rejected
    ///         rather than eating into supplier cash
    function testSweepCannotTouchSupplierCash() public {
        _mint(supplier, supplyAmount);

        vm.expectRevert("MErc20::sweepTokenAndSync: amount exceeds surplus");
        mToken.sweepTokenAndSync(1);

        mToken.sweepTokenAndSync(0);

        assertEq(mToken.internalCash(), supplyAmount, "internalCash moved");
    }

    /// @notice sweeping zero credits the donation to suppliers through the exchange rate
    function testSweepZeroCreditsDonationToSuppliers() public {
        _mint(supplier, supplyAmount);

        uint256 exchangeRateBefore = mToken.exchangeRateStored();

        _donate(donationAmount);

        vm.expectEmit(true, true, true, true, address(mToken));
        emit CashSynced(supplyAmount, supplyAmount + donationAmount);
        mToken.sweepTokenAndSync(0);

        assertEq(
            mToken.internalCash(),
            supplyAmount + donationAmount,
            "internalCash not resynced"
        );
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
        assertGt(
            mToken.exchangeRateStored(),
            exchangeRateBefore,
            "donation not credited to suppliers"
        );

        /// the supplier now redeems the donation along with their own deposit
        uint256 supplierTokens = mToken.balanceOf(supplier);

        vm.prank(supplier);
        assertEq(
            mToken.redeem(supplierTokens),
            uint(Error.NO_ERROR),
            "redeem failed"
        );
        assertEq(
            token.balanceOf(supplier),
            supplyAmount + donationAmount,
            "supplier did not receive the donation"
        );
    }

    /// @notice sweeping the whole surplus hands it to the admin and leaves suppliers
    ///         exactly where they were
    function testSweepFullSurplusToAdmin() public {
        _mint(supplier, supplyAmount);

        uint256 exchangeRateBefore = mToken.exchangeRateStored();

        _donate(donationAmount);

        vm.expectEmit(true, true, true, true, address(mToken));
        emit UnderlyingSwept(address(this), donationAmount);
        vm.expectEmit(true, true, true, true, address(mToken));
        emit CashSynced(supplyAmount, supplyAmount);
        mToken.sweepTokenAndSync(donationAmount);

        assertEq(
            token.balanceOf(address(this)),
            donationAmount,
            "admin did not receive the surplus"
        );
        assertEq(mToken.internalCash(), supplyAmount, "internalCash moved");
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
        assertEq(
            mToken.exchangeRateStored(),
            exchangeRateBefore,
            "exchange rate moved"
        );
    }

    /// @notice what is left behind by a partial sweep is credited to suppliers
    function testSweepPartialSurplusSplitsBetweenAdminAndSuppliers() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);

        uint256 sweepAmount = donationAmount / 4;
        uint256 remainder = donationAmount - sweepAmount;

        mToken.sweepTokenAndSync(sweepAmount);

        assertEq(
            token.balanceOf(address(this)),
            sweepAmount,
            "admin did not receive the swept portion"
        );
        assertEq(
            mToken.internalCash(),
            supplyAmount + remainder,
            "remainder not credited"
        );
        assertEq(
            mToken.internalCash(),
            token.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
    }

    /// @notice interest is booked at the pre sweep utilization, so the sweep cannot be
    ///         timed to accrue against a cash balance that is about to change
    function testSweepAccruesInterestBeforeSyncing() public {
        _mint(supplier, supplyAmount);
        _borrow(supplier, supplyAmount / 4);
        _donate(donationAmount);

        vm.warp(block.timestamp + 30 days);

        uint256 borrowsBefore = mToken.totalBorrows();

        mToken.sweepTokenAndSync(0);

        assertEq(
            mToken.accrualBlockTimestamp(),
            block.timestamp,
            "interest not accrued"
        );
        assertGt(mToken.totalBorrows(), borrowsBefore, "borrows did not grow");
    }

    /// ---------------------------------------------------------------------------
    /// _becomeImplementation seeding
    /// ---------------------------------------------------------------------------

    /// @notice the state a live market is in the moment before it is upgraded: real
    ///         underlying on hand, but no `internalCash` recorded yet
    function testBecomeImplementationSeedsInternalCashFromBalance() public {
        _mint(supplier, supplyAmount);

        uint256 exchangeRateBefore = mToken.exchangeRateStored();

        _clearCashTracking();

        assertEq(
            mToken.getCash(),
            0,
            "precondition: market should read zero cash while untracked"
        );

        MErc20Delegate newImplementation = new MErc20Delegate();

        vm.expectEmit(true, true, true, true, address(mToken));
        emit CashSynced(0, supplyAmount);
        mToken._setImplementation(address(newImplementation), true, "");

        assertTrue(
            mToken.internalCashInitialized(),
            "cash tracking not initialized"
        );
        assertEq(
            mToken.internalCash(),
            supplyAmount,
            "internalCash not seeded"
        );
        assertEq(
            mToken.exchangeRateStored(),
            exchangeRateBefore,
            "upgrade moved the exchange rate"
        );
    }

    /// @notice a donation sitting in the market at upgrade time is seeded into
    ///         `internalCash` because it is indistinguishable from supplier cash at that
    ///         point; every donation after the upgrade is not
    function testBecomeImplementationDoesNotReseedAfterInitialization() public {
        _mint(supplier, supplyAmount);
        _donate(donationAmount);

        MErc20Delegate newImplementation = new MErc20Delegate();
        mToken._setImplementation(address(newImplementation), true, "");

        assertEq(
            mToken.internalCash(),
            supplyAmount,
            "second upgrade reseeded internalCash from the donation"
        );
        assertEq(
            mToken.getCash(),
            supplyAmount,
            "donation reached getCash through the upgrade"
        );
    }

    /// @notice the rollback path called out in `_becomeImplementation`: cash tracking is
    ///         already initialized, so rolling forward again leaves `internalCash` stale
    ///         and the admin has to resync it explicitly
    function testStaleCashAfterRollForwardIsFixedBySweepZero() public {
        _mint(supplier, supplyAmount);

        /// emulate a market that spent time on a balance based implementation: cash moved
        /// while `internalCash` was not being maintained
        vm.store(address(mToken), bytes32(INTERNAL_CASH_SLOT), bytes32(0));

        MErc20Delegate newImplementation = new MErc20Delegate();
        mToken._setImplementation(address(newImplementation), true, "");

        assertEq(
            mToken.internalCash(),
            0,
            "upgrade reseeded an already initialized market"
        );

        mToken.sweepTokenAndSync(0);

        assertEq(
            mToken.internalCash(),
            supplyAmount,
            "resync did not restore the tracked cash"
        );
    }

    /// ---------------------------------------------------------------------------
    /// helpers
    /// ---------------------------------------------------------------------------

    function _mint(address user, uint256 amount) private {
        token.allocateTo(user, amount);

        vm.startPrank(user);
        token.approve(address(mToken), amount);
        assertEq(mToken.mint(amount), uint(Error.NO_ERROR), "mint failed");
        vm.stopPrank();
    }

    function _borrow(address user, uint256 amount) private {
        address[] memory markets = new address[](1);
        markets[0] = address(mToken);

        vm.startPrank(user);
        comptroller.enterMarkets(markets);
        assertEq(mToken.borrow(amount), uint(Error.NO_ERROR), "borrow failed");
        vm.stopPrank();
    }

    /// @dev collateral in the second market, so a borrow against it is limited by the
    ///      first market's cash rather than by the borrower's collateral
    function _supplyCollateral(address user, uint256 amount) private {
        collateralToken.allocateTo(user, amount);

        address[] memory markets = new address[](1);
        markets[0] = address(mCollateral);

        vm.startPrank(user);
        collateralToken.approve(address(mCollateral), amount);
        assertEq(
            mCollateral.mint(amount),
            uint(Error.NO_ERROR),
            "collateral mint failed"
        );
        comptroller.enterMarkets(markets);
        vm.stopPrank();
    }

    /// @dev underlying sent straight to the market, never through `doTransferIn`
    function _donate(uint256 amount) private {
        token.allocateTo(donor, amount);

        vm.prank(donor);
        token.transfer(address(mToken), amount);
    }

    /// @dev rewinds the two cash tracking slots to what a market looks like before it has
    ///      ever run an implementation that maintains them
    function _clearCashTracking() private {
        vm.store(address(mToken), bytes32(INTERNAL_CASH_SLOT), bytes32(0));
        vm.store(
            address(mToken),
            bytes32(INTERNAL_CASH_INITIALIZED_SLOT),
            bytes32(0)
        );

        assertEq(mToken.internalCash(), 0, "internalCash slot mismatch");
        assertFalse(
            mToken.internalCashInitialized(),
            "internalCashInitialized slot mismatch"
        );
    }
}

/// @notice `MWethDelegate` routes its transfers out through the unwrapper, so this checks
///         that the WETH market debits `internalCash` exactly once on the way out and that
///         donations are just as inert there as on a plain ERC-20 market.
contract MWethDelegateInternalCashUnitTest is Test, TokenErrorReporter {
    Comptroller public comptroller;
    SimplePriceOracle public oracle;
    MockWeth public weth;
    WethUnwrapper public unwrapper;
    MErc20Delegator public mToken;

    address public constant supplier = address(0x51);

    uint256 public constant supplyAmount = 10 ether;
    uint256 public constant donationAmount = 1 ether;

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        weth = new MockWeth();
        unwrapper = new WethUnwrapper(address(weth));

        mToken = new MErc20Delegator(
            address(weth),
            comptroller,
            new WhitePaperInterestRateModel(0.1e18, 0.45e18),
            1e18,
            "Moonwell WETH",
            "mWETH",
            8,
            payable(address(this)),
            address(new MWethDelegate(address(unwrapper))),
            ""
        );

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(this),
            abi.encodeWithSignature(
                "initialize(address,address)",
                address(comptroller),
                address(this)
            )
        );

        comptroller._setRewardDistributor(
            MultiRewardDistributor(address(proxy))
        );
        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(MToken(address(mToken)));
        oracle.setUnderlyingPrice(MToken(address(mToken)), 1e18);
    }

    /// @notice the unwrapping transfer out debits `internalCash` once, not twice, and the
    ///         redeemer is paid in raw ETH
    function testRedeemDebitsInternalCashOnce() public {
        _mint(supplyAmount);

        uint256 redeemAmount = supplyAmount / 2;
        uint256 ethBefore = supplier.balance;

        vm.prank(supplier);
        assertEq(
            mToken.redeemUnderlying(redeemAmount),
            uint(Error.NO_ERROR),
            "redeem failed"
        );

        assertEq(
            mToken.internalCash(),
            supplyAmount - redeemAmount,
            "internalCash debited more than once"
        );
        assertEq(
            mToken.internalCash(),
            weth.balanceOf(address(mToken)),
            "internalCash diverged from balance"
        );
        assertEq(
            supplier.balance - ethBefore,
            redeemAmount,
            "redeemer not paid in ETH"
        );
    }

    function testDonationDoesNotMoveCash() public {
        _mint(supplyAmount);

        uint256 exchangeRateBefore = mToken.exchangeRateStored();

        vm.deal(address(this), donationAmount);
        weth.deposit{value: donationAmount}();
        weth.transfer(address(mToken), donationAmount);

        assertEq(mToken.getCash(), supplyAmount, "getCash moved");
        assertEq(
            mToken.exchangeRateStored(),
            exchangeRateBefore,
            "exchange rate moved"
        );

        /// the sweep hands WETH, not raw ETH, to the admin
        mToken.sweepTokenAndSync(donationAmount);

        assertEq(
            weth.balanceOf(address(this)),
            donationAmount,
            "admin did not receive WETH"
        );
        assertEq(mToken.internalCash(), supplyAmount, "internalCash moved");
    }

    function _mint(uint256 amount) private {
        vm.deal(supplier, amount);

        vm.startPrank(supplier);
        weth.deposit{value: amount}();
        weth.approve(address(mToken), amount);
        assertEq(mToken.mint(amount), uint(Error.NO_ERROR), "mint failed");
        vm.stopPrank();
    }

    receive() external payable {}
}

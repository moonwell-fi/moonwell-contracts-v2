pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MDelegateInterface} from "@protocol/MTokenInterfaces.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {FaucetToken} from "@test/helper/FaucetToken.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {WhitePaperInterestRateModel} from "@protocol/irm/WhitePaperInterestRateModel.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {TokenErrorReporter} from "@protocol/TokenErrorReporter.sol";

/// @notice mirrors the pre-upgrade MErc20Delegate: cash = underlying.balanceOf
contract LegacyBalanceOfDelegate is MErc20, MDelegateInterface {
    function _becomeImplementation(bytes memory) public virtual override {
        require(msg.sender == admin, "only admin");
    }

    function _resignImplementation() public virtual override {
        require(msg.sender == admin, "only admin");
    }
}

/// @notice ERC20 that burns 1% of every transfer, to pin fee-on-transfer credit
contract FeeOnTransferToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;
    uint8 public constant decimals = 18;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        _transfer(from, to, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) internal {
        uint256 fee = amount / 100;
        balanceOf[from] -= amount;
        balanceOf[to] += amount - fee;
        totalSupply -= fee;
    }
}

contract MErc20DelegateInternalCashUnitTest is Test {
    event ExcessCashSwept(address indexed recipient, uint256 amount);

    Comptroller comptroller;
    SimplePriceOracle oracle;
    FaucetToken token;
    MErc20Delegator delegator;
    MErc20Delegate impl;
    MToken mToken;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address donor = address(0xD0D0);

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        token = new FaucetToken(0, "Testing", 18, "TEST");
        InterestRateModel irm = new WhitePaperInterestRateModel(
            0.1e18,
            0.45e18
        );

        // start on the legacy implementation, as live markets do
        LegacyBalanceOfDelegate legacy = new LegacyBalanceOfDelegate();
        impl = new MErc20Delegate();

        delegator = new MErc20Delegator(
            address(token),
            comptroller,
            irm,
            1e18,
            "Test mToken",
            "mTEST",
            8,
            payable(address(this)),
            address(legacy),
            ""
        );
        mToken = MToken(address(delegator));

        MultiRewardDistributor distributor = new MultiRewardDistributor();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(0xdead),
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
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);
        comptroller._setCollateralFactor(mToken, 0.5e18);
    }

    function _mint(address who, uint256 amount) internal {
        token.allocateTo(who, amount);
        vm.startPrank(who);
        token.approve(address(mToken), amount);
        assertEq(MErc20(address(mToken)).mint(amount), 0, "mint failed");
        vm.stopPrank();
    }

    function _donate(uint256 amount) internal {
        token.allocateTo(donor, amount);
        vm.prank(donor);
        token.transfer(address(mToken), amount);
    }

    function _upgrade() internal {
        delegator._setImplementation(address(impl), true, "");
    }

    function _internalCash() internal view returns (uint256) {
        return MErc20Delegate(address(mToken)).internalCash();
    }

    /// @dev underlying leaves the market outside the protocol (seizure / burn)
    function _lose(uint256 amount) internal {
        vm.prank(address(mToken));
        token.transfer(address(0xdead), amount);
    }

    /// @dev alice supplies 100, bob supplies 20 and borrows 10, then 65 is
    ///      lost: internalCash 110, balance 45, borrows 10, supply 120
    function _lossWithBorrows() internal {
        _upgrade();
        _mint(alice, 100e18);
        _mint(bob, 20e18);

        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        vm.startPrank(bob);
        comptroller.enterMarkets(markets);
        assertEq(MErc20(address(mToken)).borrow(10e18), 0);
        vm.stopPrank();

        assertEq(mToken.exchangeRateStored(), 1e18);
        _lose(65e18);
    }

    function testUpgradeSyncsInternalCashAndKeepsExchangeRate() public {
        _mint(alice, 100e18);
        _donate(7e18); // pre-upgrade donation is absorbed, as today

        uint256 rateBefore = mToken.exchangeRateStored();
        uint256 cashBefore = mToken.getCash();

        _upgrade();

        assertEq(_internalCash(), token.balanceOf(address(mToken)));
        assertEq(mToken.getCash(), cashBefore, "getCash moved on upgrade");
        assertEq(
            mToken.exchangeRateStored(),
            rateBefore,
            "exchange rate moved on upgrade"
        );
    }

    function testDonationDoesNotMoveExchangeRateOrCash() public {
        _upgrade();
        _mint(alice, 100e18);

        uint256 rateBefore = mToken.exchangeRateStored();
        _donate(1_000e18);

        assertEq(mToken.getCash(), 100e18);
        assertEq(mToken.exchangeRateStored(), rateBefore);
        assertEq(token.balanceOf(address(mToken)), 1_100e18);
    }

    function testDonationDoesNotCountTowardSupplyCap() public {
        _upgrade();

        MToken[] memory mTokens = new MToken[](1);
        mTokens[0] = mToken;
        uint256[] memory caps = new uint256[](1);
        caps[0] = 100e18;
        comptroller._setMarketSupplyCaps(mTokens, caps);

        _mint(alice, 90e18);
        _donate(1_000e18);

        // donation is invisible to the cap: alice can still fill it
        _mint(alice, 9e18);

        // and alice's collateral never exceeds what went through mint
        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        vm.prank(alice);
        comptroller.enterMarkets(markets);
        (, uint256 liquidity, ) = comptroller.getAccountLiquidity(alice);
        assertEq(liquidity, (99e18 * 0.5e18) / 1e18);

        // the cap still binds on real mints
        token.allocateTo(bob, 2e18);
        vm.startPrank(bob);
        token.approve(address(mToken), 2e18);
        vm.expectRevert("market supply cap reached");
        MErc20(address(mToken)).mint(2e18);
        vm.stopPrank();
    }

    function testMintRedeemBorrowRepayTrackInternalCash() public {
        _upgrade();
        _mint(alice, 100e18);
        _mint(bob, 50e18);
        assertEq(_internalCash(), 150e18);

        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        vm.prank(bob);
        comptroller.enterMarkets(markets);

        vm.prank(bob);
        assertEq(MErc20(address(mToken)).borrow(20e18), 0);
        assertEq(_internalCash(), 130e18);

        vm.startPrank(bob);
        token.approve(address(mToken), 20e18);
        assertEq(MErc20(address(mToken)).repayBorrow(20e18), 0);
        vm.stopPrank();
        assertEq(_internalCash(), 150e18);

        vm.prank(alice);
        assertEq(MErc20(address(mToken)).redeemUnderlying(40e18), 0);
        assertEq(_internalCash(), 110e18);
        assertEq(_internalCash(), token.balanceOf(address(mToken)));
    }

    function testSweepExcessCashOnlySendsDonation() public {
        _upgrade();
        _mint(alice, 100e18);
        _donate(25e18);

        uint256 adminBefore = token.balanceOf(address(this));
        vm.expectEmit(true, false, false, true, address(mToken));
        emit ExcessCashSwept(address(this), 25e18);
        MErc20Delegate(address(mToken))._sweepExcessCash();

        assertEq(token.balanceOf(address(this)) - adminBefore, 25e18);
        assertEq(token.balanceOf(address(mToken)), 100e18);
        assertEq(_internalCash(), 100e18);

        // nothing left to sweep: no-op, no event
        vm.recordLogs();
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(token.balanceOf(address(this)) - adminBefore, 25e18);
        assertEq(vm.getRecordedLogs().length, 0, "no-op sweep emitted");
    }

    function testLaterUpgradeDoesNotAbsorbDonation() public {
        _upgrade();
        _mint(alice, 100e18);
        _donate(1_000e18);
        uint256 rateBefore = mToken.exchangeRateStored();

        uint256 adminBefore = token.balanceOf(address(this));
        delegator._setImplementation(address(new MErc20Delegate()), true, "");

        assertEq(_internalCash(), 100e18);
        assertEq(mToken.exchangeRateStored(), rateBefore);
        assertEq(token.balanceOf(address(this)) - adminBefore, 1_000e18);
    }

    function testRollbackAndReupgradeResyncs() public {
        _upgrade();
        _mint(alice, 100e18);

        // incident rollback to the balanceOf implementation
        delegator._setImplementation(
            address(new LegacyBalanceOfDelegate()),
            true,
            ""
        );

        // balance moves while internalCash is ignored
        vm.prank(alice);
        assertEq(MErc20(address(mToken)).redeemUnderlying(40e18), 0);
        _mint(bob, 10e18);

        _upgrade();
        assertEq(_internalCash(), token.balanceOf(address(mToken)));
        assertEq(_internalCash(), 70e18);
    }

    function testDirectResignOnlySweeps() public {
        _upgrade();
        _mint(alice, 100e18);
        _donate(5e18);

        uint256 adminBefore = token.balanceOf(address(this));
        MErc20Delegate(address(mToken))._resignImplementation();

        assertEq(mToken.getCash(), 100e18);
        assertEq(token.balanceOf(address(this)) - adminBefore, 5e18);
    }

    function testRollbackWithoutResignDoesNotGoStale() public {
        _upgrade();
        _mint(alice, 100e18);

        address legacy = address(new LegacyBalanceOfDelegate());
        delegator._setImplementation(legacy, false, "");
        _mint(bob, 50e18);
        delegator._setImplementation(address(impl), false, "");

        assertEq(_internalCash(), 150e18);

        uint256 adminBefore = token.balanceOf(address(this));
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(token.balanceOf(address(this)), adminBefore);
    }

    /// @notice documented: without resign there is no sweep, so a pending
    /// donation is absorbed. Governance always passes allowResign = true.
    function testUpgradeWithoutResignAbsorbsPendingDonation() public {
        _upgrade();
        _mint(alice, 100e18);
        _donate(5e18);

        delegator._setImplementation(address(new MErc20Delegate()), false, "");

        assertEq(_internalCash(), 105e18);
    }

    function testZeroCashMarketDoesNotAbsorbDonationOnUpgrade() public {
        _upgrade();
        _donate(50e18); // internalCash is legitimately 0

        uint256 adminBefore = token.balanceOf(address(this));
        delegator._setImplementation(address(new MErc20Delegate()), true, "");

        assertEq(_internalCash(), 0);
        assertEq(token.balanceOf(address(this)) - adminBefore, 50e18);
    }

    function testSyncCashDownOnlyLowers() public {
        _upgrade();
        _mint(alice, 100e18);

        // donation above internalCash is not absorbed
        _donate(10e18);
        MErc20Delegate(address(mToken))._syncCashDown();
        assertEq(_internalCash(), 100e18);

        // issuer seizure below internalCash is recognized
        vm.prank(address(mToken));
        token.transfer(address(0xdead), 40e18);
        MErc20Delegate(address(mToken))._syncCashDown();
        assertEq(_internalCash(), 70e18);

        // sweep is a no-op once balance == internalCash
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(_internalCash(), 70e18);
    }

    function testSyncCashDownOnlyAdmin() public {
        _upgrade();
        vm.prank(alice);
        vm.expectRevert("only the admin may sync cash");
        MErc20Delegate(address(mToken))._syncCashDown();
    }

    function testSweepExcessCashNoopWhenBalanceBelowInternalCash() public {
        _upgrade();
        _mint(alice, 100e18);
        vm.prank(address(mToken));
        token.transfer(address(0xdead), 1e18);

        uint256 adminBefore = token.balanceOf(address(this));
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(token.balanceOf(address(this)), adminBefore);
    }

    function testNonAdminCannotCallBecomeImplementationDirectly() public {
        _upgrade();
        vm.prank(alice);
        vm.expectRevert("only the admin may call _becomeImplementation");
        MErc20Delegate(address(mToken))._becomeImplementation("");
    }

    function testNonAdminCannotCallResignImplementationDirectly() public {
        _upgrade();
        vm.prank(alice);
        vm.expectRevert("only the admin may call _resignImplementation");
        MErc20Delegate(address(mToken))._resignImplementation();
    }

    function testFeeOnTransferCreditsAmountReceived() public {
        FeeOnTransferToken fot = new FeeOnTransferToken();
        MErc20Delegator fotDelegator = new MErc20Delegator(
            address(fot),
            comptroller,
            new WhitePaperInterestRateModel(0.1e18, 0.45e18),
            1e18,
            "Fee mToken",
            "mFEE",
            8,
            payable(address(this)),
            address(impl),
            ""
        );
        MToken fotMarket = MToken(address(fotDelegator));
        comptroller._supportMarket(fotMarket);
        oracle.setUnderlyingPrice(fotMarket, 1e18);

        fot.mint(alice, 100e18);
        vm.startPrank(alice);
        fot.approve(address(fotMarket), 100e18);
        assertEq(MErc20(address(fotMarket)).mint(100e18), 0);
        vm.stopPrank();

        assertEq(MErc20Delegate(address(fotMarket)).internalCash(), 99e18);
        assertEq(fot.balanceOf(address(fotMarket)), 99e18);
    }

    /// @dev mint 150, borrow 20, lose 60 outside the market, one year passes
    function _lossAfterAYear() internal {
        _upgrade();
        _mint(alice, 100e18);
        _mint(bob, 50e18);

        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        vm.startPrank(bob);
        comptroller.enterMarkets(markets);
        assertEq(MErc20(address(mToken)).borrow(20e18), 0);
        vm.stopPrank();

        vm.prank(address(mToken));
        token.transfer(address(0xdead), 60e18);
        vm.warp(block.timestamp + 365 days);
    }

    function testDirectBecomeAccruesLikeSyncCashDown() public {
        _lossAfterAYear();

        // the elapsed year is priced at the post-loss cash (70), not 130
        uint256 rate = mToken.interestRateModel().getBorrowRate(
            70e18,
            20e18,
            0
        );
        uint256 expectedBorrows = 20e18 + (rate * 365 days * 20e18) / 1e18;

        uint256 snapshot = vm.snapshot();

        MErc20Delegate(address(mToken))._becomeImplementation("");
        uint256 borrowsViaBecome = mToken.totalBorrows();
        assertEq(_internalCash(), 70e18);

        vm.revertTo(snapshot);
        MErc20Delegate(address(mToken))._syncCashDown();
        uint256 borrowsViaSyncDown = mToken.totalBorrows();
        assertEq(_internalCash(), 70e18);

        // both accrue the elapsed year at the post-loss cash before syncing
        assertGt(borrowsViaSyncDown, 20e18);
        assertEq(borrowsViaBecome, borrowsViaSyncDown);
        assertEq(borrowsViaSyncDown, expectedBorrows);
    }

    function testLossIsPricedImmediately() public {
        _lossWithBorrows();

        // no governance action: cash is the real balance, internalCash kept
        assertEq(mToken.getCash(), 45e18);
        assertEq(_internalCash(), 110e18);

        // all suppliers share the loss pro rata: (45 + 10) / 120
        uint256 expectedRate = (uint256(55e18) * 1e18) / 120e18;
        assertEq(mToken.exchangeRateStored(), expectedRate);
        assertEq(mToken.exchangeRateCurrent(), expectedRate);

        // redeeming alice's whole position (worth 100 pre-loss, ~45.83 now)
        // exceeds the 45 left and fails cleanly with the cash error instead
        // of reverting inside the token transfer
        vm.prank(alice);
        assertEq(
            MErc20(address(mToken)).redeem(100e18),
            uint256(TokenErrorReporter.Error.TOKEN_INSUFFICIENT_CASH)
        );
        assertEq(mToken.balanceOf(alice), 100e18);
        assertEq(token.balanceOf(address(mToken)), 45e18);

        // what is actually there can still be paid out
        vm.prank(alice);
        assertEq(MErc20(address(mToken)).redeemUnderlying(45e18), 0);
        assertEq(_internalCash(), 65e18);
        assertEq(mToken.getCash(), 0);
    }

    function testReturnedTokensRestoreCashWithoutGovernance() public {
        _lossWithBorrows();
        uint256 lossRate = mToken.exchangeRateStored();

        // half comes back: cash and exchange rate rise by exactly that much
        token.allocateTo(address(mToken), 30e18);
        assertEq(mToken.getCash(), 75e18);
        assertEq(mToken.exchangeRateStored(), (uint256(85e18) * 1e18) / 120e18);
        assertGt(mToken.exchangeRateStored(), lossRate);

        // the rest comes back: fully restored to internalCash
        token.allocateTo(address(mToken), 35e18);
        assertEq(mToken.getCash(), 110e18);
        assertEq(mToken.exchangeRateStored(), 1e18);

        // anything beyond internalCash is a donation again: ignored
        _donate(5e18);
        assertEq(mToken.getCash(), 110e18);
        assertEq(mToken.exchangeRateStored(), 1e18);
        assertEq(_internalCash(), 110e18);
    }

    function testReturnedTokensAfterSyncCashDownAreExcess() public {
        _lossWithBorrows();
        MErc20Delegate(address(mToken))._syncCashDown();
        assertEq(_internalCash(), 45e18);
        uint256 syncedRate = mToken.exchangeRateStored();

        // the loss is permanent: returned tokens do not raise cash
        token.allocateTo(address(mToken), 65e18);
        assertEq(mToken.getCash(), 45e18);
        assertEq(mToken.exchangeRateStored(), syncedRate);

        // and are sweepable as excess
        uint256 adminBefore = token.balanceOf(address(this));
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(token.balanceOf(address(this)) - adminBefore, 65e18);
        assertEq(mToken.getCash(), 45e18);
    }

    function testDonationIgnoredWithMinCash() public {
        _upgrade();
        _mint(alice, 100e18);
        _donate(50e18);

        assertEq(token.balanceOf(address(mToken)), 150e18);
        assertEq(mToken.getCash(), 100e18);

        // a loss smaller than the donation is absorbed by the donation
        _lose(30e18);
        assertEq(mToken.getCash(), 100e18);
        assertEq(mToken.exchangeRateStored(), 1e18);

        // only the part below internalCash is priced
        _lose(30e18);
        assertEq(mToken.getCash(), 90e18);
    }

    function testMigrationDoesNotAccrue() public {
        _mint(alice, 100e18);
        _mint(bob, 50e18);

        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        vm.startPrank(bob);
        comptroller.enterMarkets(markets);
        assertEq(MErc20(address(mToken)).borrow(20e18), 0);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);
        uint256 borrowsBefore = mToken.totalBorrows();
        uint256 accrualBefore = mToken.accrualBlockTimestamp();

        _upgrade();

        assertEq(mToken.totalBorrows(), borrowsBefore);
        assertEq(mToken.accrualBlockTimestamp(), accrualBefore);
        assertEq(_internalCash(), 130e18);
    }

    function testSweepExcessCashOnlyAdmin() public {
        _upgrade();
        vm.prank(alice);
        vm.expectRevert("only the admin may sweep excess cash");
        MErc20Delegate(address(mToken))._sweepExcessCash();
    }

    function testBecomeImplementationOnlyAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            "MErc20Delegator::_setImplementation: Caller must be admin"
        );
        delegator._setImplementation(address(impl), true, "");
    }

    function testFuzzLossPricedProRata(uint96 supply, uint96 loss) public {
        supply = uint96(bound(supply, 1e6, type(uint96).max));
        loss = uint96(bound(loss, 0, supply - 1));
        _upgrade();
        _mint(alice, supply);
        _lose(loss);

        assertEq(mToken.getCash(), uint256(supply) - loss);
        assertEq(
            mToken.exchangeRateStored(),
            ((uint256(supply) - loss) * 1e18) / mToken.totalSupply()
        );
        assertEq(_internalCash(), supply);
    }

    function testFuzzDonationNeverChangesExchangeRate(
        uint96 supply,
        uint96 donation
    ) public {
        supply = uint96(bound(supply, 1e6, type(uint96).max));
        _upgrade();
        _mint(alice, supply);
        uint256 rateBefore = mToken.exchangeRateStored();
        _donate(donation);
        assertEq(mToken.exchangeRateStored(), rateBefore);
        assertEq(mToken.getCash(), supply);
    }
}

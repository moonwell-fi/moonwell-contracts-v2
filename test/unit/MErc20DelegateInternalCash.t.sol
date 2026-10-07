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

/// @notice mirrors the pre-upgrade MErc20Delegate: cash = underlying.balanceOf
contract LegacyBalanceOfDelegate is MErc20, MDelegateInterface {
    function _becomeImplementation(bytes memory) public virtual override {
        require(msg.sender == admin, "only admin");
    }

    function _resignImplementation() public virtual override {
        require(msg.sender == admin, "only admin");
    }
}

contract MErc20DelegateInternalCashUnitTest is Test {
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
        MErc20Delegate(address(mToken))._sweepExcessCash();

        assertEq(token.balanceOf(address(this)) - adminBefore, 25e18);
        assertEq(token.balanceOf(address(mToken)), 100e18);
        assertEq(_internalCash(), 100e18);

        // nothing left to sweep: no-op
        MErc20Delegate(address(mToken))._sweepExcessCash();
        assertEq(token.balanceOf(address(this)) - adminBefore, 25e18);
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

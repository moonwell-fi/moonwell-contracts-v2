// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ComptrollerInterface} from "@protocol/ComptrollerInterface.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Verifies that pointing a live market at a delegate compiled from the merged
///         `MTokenStorage` layout leaves every storage backed value reading the same.
///         `underlying` and `implementation` moved out of `MErc20Storage` and
///         `MDelegationStorage` into `MTokenStorage`; if that move shifted a slot, the new
///         implementation would read different values through the delegator's storage.
/// @dev Run against a Base fork: `forge test --match-contract MTokenStorageUpgradeIntegrationTest --fork-url base`
contract MTokenStorageUpgradeIntegrationTest is Test {
    Addresses private addresses;

    /// @notice Every value the delegator serves out of storage, read through whichever
    ///         implementation is currently wired in. Fields follow MTokenStorage slot
    ///         order so a shifted slot is easy to spot from the failing assertion.
    ///         Slot 0 `_notEntered` and slot 7 `initialExchangeRateMantissa` are internal
    ///         with no getter; slot 19 `implementation` changes and is checked separately.
    struct MarketState {
        string name; // slot 1
        string symbol; // slot 2
        uint8 decimals; // slot 3
        address admin; // slot 3
        address pendingAdmin; // slot 4
        address comptroller; // slot 5
        address interestRateModel; // slot 6
        uint256 reserveFactorMantissa; // slot 8
        uint256 accrualBlockTimestamp; // slot 9
        uint256 borrowIndex; // slot 10
        uint256 totalBorrows; // slot 11
        uint256 totalReserves; // slot 12
        uint256 totalSupply; // slot 13
        uint256 holderBalance; // slot 14, accountTokens
        uint256 holderAllowance; // slot 15, transferAllowances
        uint256 holderBorrow; // slot 16, accountBorrows
        uint256 protocolSeizeShareMantissa; // slot 17
        address underlying; // slot 18
        uint256 exchangeRateStored; // derived from the above
        uint256 cash; // derived from the above
    }

    function setUp() public {
        addresses = new Addresses();
    }

    /// @notice a plain ERC-20 market, upgraded to a freshly compiled MErc20Delegate
    function testMErc20MarketStorageSurvivesUpgrade() public {
        _assertStorageSurvivesUpgrade(
            addresses.getAddress("MOONWELL_USDC"),
            address(new MErc20Delegate()),
            1_000e6
        );
    }

    /// @notice the WETH market, which runs its own delegate, upgraded to a freshly
    ///         compiled MWethDelegate wired to the live unwrapper
    function testMWethMarketStorageSurvivesUpgrade() public {
        _assertStorageSurvivesUpgrade(
            addresses.getAddress("MOONWELL_WETH"),
            address(
                new MWethDelegate(addresses.getAddress("WETH_UNWRAPPER"))
            ),
            1 ether
        );
    }

    /// @notice supply and borrow so the mapping backed slots hold something, snapshot the
    ///         market through the live implementation, swap the implementation, then read
    ///         everything back and require it to be unchanged
    function _assertStorageSurvivesUpgrade(
        address market,
        address newImplementation,
        uint256 supplyAmount
    ) private {
        MErc20Delegator delegator = MErc20Delegator(payable(market));
        address oldImplementation = delegator.implementation();

        assertTrue(
            oldImplementation != newImplementation,
            "new implementation must differ from the live one"
        );

        _supplyAndBorrow(market, supplyAmount);

        MarketState memory before = _snapshot(market);

        vm.prank(delegator.admin());
        delegator._setImplementation(newImplementation, true, "");

        assertEq(
            delegator.implementation(),
            newImplementation,
            "implementation not swapped"
        );

        MarketState memory afterUpgrade = _snapshot(market);

        assertEq(afterUpgrade.name, before.name, "name");
        assertEq(afterUpgrade.symbol, before.symbol, "symbol");
        assertEq(afterUpgrade.decimals, before.decimals, "decimals");
        assertEq(afterUpgrade.admin, before.admin, "admin");
        assertEq(
            afterUpgrade.pendingAdmin,
            before.pendingAdmin,
            "pendingAdmin"
        );
        assertEq(afterUpgrade.comptroller, before.comptroller, "comptroller");
        assertEq(
            afterUpgrade.interestRateModel,
            before.interestRateModel,
            "interestRateModel"
        );
        assertEq(
            afterUpgrade.reserveFactorMantissa,
            before.reserveFactorMantissa,
            "reserveFactorMantissa"
        );
        assertEq(
            afterUpgrade.accrualBlockTimestamp,
            before.accrualBlockTimestamp,
            "accrualBlockTimestamp"
        );
        assertEq(afterUpgrade.borrowIndex, before.borrowIndex, "borrowIndex");
        assertEq(
            afterUpgrade.totalBorrows,
            before.totalBorrows,
            "totalBorrows"
        );
        assertEq(
            afterUpgrade.totalReserves,
            before.totalReserves,
            "totalReserves"
        );
        assertEq(afterUpgrade.totalSupply, before.totalSupply, "totalSupply");
        assertEq(
            afterUpgrade.holderBalance,
            before.holderBalance,
            "accountTokens"
        );
        assertEq(
            afterUpgrade.holderAllowance,
            before.holderAllowance,
            "transferAllowances"
        );
        assertEq(
            afterUpgrade.holderBorrow,
            before.holderBorrow,
            "accountBorrows"
        );
        assertEq(
            afterUpgrade.protocolSeizeShareMantissa,
            before.protocolSeizeShareMantissa,
            "protocolSeizeShareMantissa"
        );
        assertEq(afterUpgrade.underlying, before.underlying, "underlying");
        assertEq(
            afterUpgrade.exchangeRateStored,
            before.exchangeRateStored,
            "exchangeRateStored"
        );
        assertEq(afterUpgrade.cash, before.cash, "cash");
    }

    /// @dev populates accountTokens, transferAllowances and accountBorrows for this test
    ///      contract so the three mapping slots are not compared empty
    function _supplyAndBorrow(address market, uint256 supplyAmount) private {
        MErc20 mToken = MErc20(market);
        address underlying = MErc20Delegator(payable(market)).underlying();

        deal(underlying, address(this), supplyAmount);
        EIP20Interface(underlying).approve(market, supplyAmount);
        assertEq(mToken.mint(supplyAmount), 0, "mint failed");

        /// an allowance this contract grants on the mToken itself, i.e. slot 15
        MErc20Delegator(payable(market)).approve(address(0xdead), 1234);

        address[] memory markets = new address[](1);
        markets[0] = market;
        ComptrollerInterface(addresses.getAddress("UNITROLLER")).enterMarkets(
            markets
        );

        /// live markets sit at their borrow cap, so lift it for this market only. The
        /// snapshot is taken after this, so the raised cap is common to both reads
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        MToken[] memory cappedMarkets = new MToken[](1);
        cappedMarkets[0] = MToken(market);
        uint256[] memory caps = new uint256[](1);
        caps[0] = type(uint256).max;

        vm.prank(comptroller.admin());
        comptroller._setMarketBorrowCaps(cappedMarkets, caps);

        uint256 borrowAmount = supplyAmount / 4;
        assertEq(mToken.borrow(borrowAmount), 0, "borrow failed");

        /// at least what was borrowed, so accrued interest still passes
        assertGe(
            MErc20Delegator(payable(market)).borrowBalanceStored(
                address(this)
            ),
            borrowAmount,
            "borrow did not register"
        );
    }

    function _snapshot(
        address market
    ) private returns (MarketState memory state) {
        MErc20Delegator delegator = MErc20Delegator(payable(market));

        state.name = delegator.name();
        state.symbol = delegator.symbol();
        state.decimals = delegator.decimals();
        state.admin = delegator.admin();
        state.pendingAdmin = delegator.pendingAdmin();
        state.comptroller = address(delegator.comptroller());
        state.interestRateModel = address(delegator.interestRateModel());
        state.reserveFactorMantissa = delegator.reserveFactorMantissa();
        state.accrualBlockTimestamp = delegator.accrualBlockTimestamp();
        state.borrowIndex = delegator.borrowIndex();
        state.totalBorrows = delegator.totalBorrows();
        state.totalReserves = delegator.totalReserves();
        state.totalSupply = delegator.totalSupply();
        state.holderBalance = delegator.balanceOf(address(this));
        state.holderAllowance = delegator.allowance(
            address(this),
            address(0xdead)
        );
        state.holderBorrow = delegator.borrowBalanceStored(address(this));
        state.protocolSeizeShareMantissa = delegator
            .protocolSeizeShareMantissa();
        state.underlying = delegator.underlying();
        state.exchangeRateStored = delegator.exchangeRateStored();
        state.cash = delegator.getCash();
    }

    /// @dev the WETH market's delegate unwraps to raw ETH on the way out
    receive() external payable {}
}

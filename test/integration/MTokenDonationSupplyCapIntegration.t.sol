// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice Proves that the supply cap is not actually a cap on a live Base market, and
///         that the upgraded market makes it one.
///
///         `Comptroller.mintAllowed` sizes the cap off
///         `getCash() + totalBorrows - totalReserves`, and only mints are routed through
///         it. While `getCash()` is `underlying.balanceOf(market)`, anyone can transfer
///         underlying straight to a market that is already sitting at its cap and push the
///         supplies it holds past that cap, with no mint and therefore no cap check
///         anywhere in the path. The market ends up carrying more of the underlying than
///         risk management sized it for, and because the donation lands in
///         `getCash()` it also lifts the exchange rate, minting value to existing
///         suppliers out of the donor's pocket.
///
///         After the upgrade `getCash()` reads `internalCash`, which only `doTransferIn`
///         and `doTransferOut` move, so the same donation leaves both the supplies the cap
///         governs and the exchange rate exactly where they were.
/// @dev Run against a Base fork:
///      `forge test --match-contract MTokenDonationSupplyCapIntegrationTest -vvv`
contract MTokenDonationSupplyCapIntegrationTest is Test {
    /// @dev pinned because the two live market tests below assert that the implementation
    ///      these markets run today is the vulnerable one. Once the upgrade executes on
    ///      Base that stops being true at head, and they would fail as if the fix were a
    ///      regression
    uint256 private constant FORK_BLOCK = 50_590_315;

    Addresses private addresses;
    Comptroller private comptroller;

    /// @dev how much underlying the donation moves, as a multiple of the honest supply
    ///      that fills the market to its cap
    uint256 private constant DONATION_MULTIPLE = 5;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"), FORK_BLOCK);

        addresses = new Addresses();
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
    }

    /// ---------------------------------------------------------------------------
    /// the vector, against the implementation that is live today
    /// ---------------------------------------------------------------------------

    function testDonationExceedsSupplyCapOnLiveUsdcMarket() public {
        _assertDonationExceedsSupplyCap(
            addresses.getAddress("MOONWELL_USDC"),
            10_000e6
        );
    }

    function testDonationExceedsSupplyCapOnLiveWethMarket() public {
        _assertDonationExceedsSupplyCap(
            addresses.getAddress("MOONWELL_WETH"),
            5 ether
        );
    }

    /// ---------------------------------------------------------------------------
    /// the same donation, after the market is pointed at the new implementation
    /// ---------------------------------------------------------------------------

    function testDonationRespectsSupplyCapOnUpgradedUsdcMarket() public {
        _assertDonationRespectsSupplyCapAfterUpgrade(
            addresses.getAddress("MOONWELL_USDC"),
            address(new MErc20Delegate()),
            10_000e6
        );
    }

    function testDonationRespectsSupplyCapOnUpgradedWethMarket() public {
        _assertDonationRespectsSupplyCapAfterUpgrade(
            addresses.getAddress("MOONWELL_WETH"),
            address(new MWethDelegate(addresses.getAddress("WETH_UNWRAPPER"))),
            5 ether
        );
    }

    /// ---------------------------------------------------------------------------
    /// scenarios
    /// ---------------------------------------------------------------------------

    /// @notice fills the market to its supply cap through the front door, confirms the cap
    ///         is enforced against one more wei of honest supply, then walks straight past
    ///         it with a donation
    function _assertDonationExceedsSupplyCap(
        address market,
        uint256 mintAmount
    ) private {
        uint256 supplyCap = _fillMarketToSupplyCap(market, mintAmount);

        uint256 suppliesAtCap = _totalSupplies(market);
        uint256 exchangeRateAtCap = MErc20Delegator(payable(market))
            .exchangeRateStored();
        uint256 donationAmount = mintAmount * DONATION_MULTIPLE;

        _donate(market, donationAmount);

        /// the market now holds more of the underlying than the cap allows, and nothing
        /// rejected it because a plain ERC-20 transfer never touches `mintAllowed`
        assertEq(
            _totalSupplies(market),
            suppliesAtCap + donationAmount,
            "donation did not land in the supplies the cap governs"
        );
        assertGt(
            _totalSupplies(market),
            supplyCap,
            "supplies did not exceed the supply cap"
        );

        /// and the donated underlying is handed to existing suppliers through the rate
        assertGt(
            MErc20Delegator(payable(market)).exchangeRateStored(),
            exchangeRateAtCap,
            "donation did not lift the exchange rate"
        );
    }

    /// @notice the same sequence against the upgraded implementation: the cap still binds
    ///         honest supply, the donation no longer counts toward it, the exchange rate
    ///         does not move, and the admin can take the donation back out
    function _assertDonationRespectsSupplyCapAfterUpgrade(
        address market,
        address newImplementation,
        uint256 mintAmount
    ) private {
        _upgradeAndAssertAccountingUnchanged(market, newImplementation);

        uint256 supplyCap = _fillMarketToSupplyCap(market, mintAmount);

        uint256 suppliesAtCap = _totalSupplies(market);
        uint256 exchangeRateAtCap = MErc20Delegator(payable(market))
            .exchangeRateStored();
        uint256 donationAmount = mintAmount * DONATION_MULTIPLE;

        _donate(market, donationAmount);

        assertEq(
            _totalSupplies(market),
            suppliesAtCap,
            "donation reached the supplies the cap governs"
        );
        assertLt(
            _totalSupplies(market),
            supplyCap,
            "supplies exceeded the supply cap"
        );
        assertEq(
            MErc20Delegator(payable(market)).exchangeRateStored(),
            exchangeRateAtCap,
            "donation lifted the exchange rate"
        );

        _assertAdminRecoversDonation(market, donationAmount);
    }

    /// ---------------------------------------------------------------------------
    /// steps
    /// ---------------------------------------------------------------------------

    /// @dev pins the supply cap `mintAmount` above what the market currently supplies,
    ///      takes that headroom with an honest mint, and checks the cap is binding
    ///      afterwards. Returns the cap that is now in force
    function _fillMarketToSupplyCap(
        address market,
        uint256 mintAmount
    ) private returns (uint256 supplyCap) {
        supplyCap = _setSupplyCapWithHeadroom(market, mintAmount);

        assertEq(
            _mint(market, mintAmount),
            0,
            "honest mint into the headroom failed"
        );
        assertLt(
            _totalSupplies(market),
            supplyCap,
            "market was not filled to its cap"
        );

        /// the cap does bind honest supply, which is what makes the donation below a way
        /// around it rather than a way into headroom that was there all along
        address underlying = MErc20Delegator(payable(market)).underlying();
        deal(underlying, address(this), 1);
        EIP20Interface(underlying).approve(market, 1);

        vm.expectRevert("market supply cap reached");
        MErc20(market).mint(1);
    }

    /// @dev the handover seeds `internalCash` from the balance the market already holds,
    ///      so nothing about the market's accounting moves in the upgrade transaction
    function _upgradeAndAssertAccountingUnchanged(
        address market,
        address newImplementation
    ) private {
        MErc20Delegator delegator = MErc20Delegator(payable(market));

        assertTrue(
            delegator.implementation() != newImplementation,
            "new implementation must differ from the live one"
        );

        uint256 cashBefore = delegator.getCash();
        uint256 exchangeRateBefore = delegator.exchangeRateStored();

        vm.prank(delegator.admin());
        delegator._setImplementation(newImplementation, true, "");

        assertTrue(
            delegator.internalCashInitialized(),
            "cash tracking not initialized by the upgrade"
        );
        assertEq(
            delegator.internalCash(),
            EIP20Interface(delegator.underlying()).balanceOf(market),
            "internalCash not seeded from the underlying balance"
        );
        assertEq(
            delegator.getCash(),
            cashBefore,
            "upgrade moved reported cash"
        );
        assertEq(
            delegator.exchangeRateStored(),
            exchangeRateBefore,
            "upgrade moved the exchange rate"
        );
    }

    function _assertAdminRecoversDonation(
        address market,
        uint256 amount
    ) private {
        MErc20Delegator delegator = MErc20Delegator(payable(market));
        address underlying = delegator.underlying();
        address admin = delegator.admin();

        uint256 adminBalanceBefore = EIP20Interface(underlying).balanceOf(
            admin
        );
        uint256 internalCashBefore = delegator.internalCash();

        vm.prank(admin);
        delegator.sweepTokenAndSync(amount);

        assertEq(
            EIP20Interface(underlying).balanceOf(admin) - adminBalanceBefore,
            amount,
            "admin did not recover the donation"
        );
        assertEq(
            delegator.internalCash(),
            internalCashBefore,
            "sweep moved supplier cash"
        );
        assertEq(
            delegator.internalCash(),
            EIP20Interface(underlying).balanceOf(market),
            "internalCash diverged from the balance after the sweep"
        );
    }

    /// ---------------------------------------------------------------------------
    /// helpers
    /// ---------------------------------------------------------------------------

    /// @dev exactly what `Comptroller.mintAllowed` measures the cap against
    function _totalSupplies(address market) private view returns (uint256) {
        MErc20Delegator delegator = MErc20Delegator(payable(market));

        return
            delegator.getCash() +
            delegator.totalBorrows() -
            delegator.totalReserves();
    }

    /// @dev pins the market's supply cap at exactly `headroom` above what it currently
    ///      supplies, so the cap arithmetic in the assertions is exact rather than
    ///      dependent on whatever the live cap happens to be
    function _setSupplyCapWithHeadroom(
        address market,
        uint256 headroom
    ) private returns (uint256 supplyCap) {
        /// accrue first so `totalBorrows` and `totalReserves` do not move underneath the
        /// cap when the next state changing call accrues for us
        assertEq(
            MErc20Delegator(payable(market)).accrueInterest(),
            0,
            "accrue interest failed"
        );

        /// `mintAllowed` requires `nextTotalSupplies < supplyCap`, so the cap is one above
        /// the headroom that has to be usable
        supplyCap = _totalSupplies(market) + headroom + 1;

        MToken[] memory markets = new MToken[](1);
        markets[0] = MToken(market);
        uint256[] memory caps = new uint256[](1);
        caps[0] = supplyCap;

        vm.prank(comptroller.admin());
        comptroller._setMarketSupplyCaps(markets, caps);
    }

    function _mint(
        address market,
        uint256 mintAmount
    ) private returns (uint256) {
        address underlying = MErc20Delegator(payable(market)).underlying();

        deal(underlying, address(this), mintAmount);
        EIP20Interface(underlying).approve(market, mintAmount);

        return MErc20(market).mint(mintAmount);
    }

    /// @dev underlying transferred straight to the market, never through `doTransferIn`
    function _donate(address market, uint256 amount) private {
        address underlying = MErc20Delegator(payable(market)).underlying();
        address attacker = address(0xA77ACE4);

        deal(underlying, attacker, amount);

        vm.prank(attacker);
        EIP20Interface(underlying).transfer(market, amount);
    }

    /// @dev the WETH market's delegate unwraps to raw ETH on the way out
    receive() external payable {}
}

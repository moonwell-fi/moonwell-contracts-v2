// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MWethOwnerWrapper} from "@protocol/MWethOwnerWrapper.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID} from "@utils/ChainIds.sol";

/// @notice MIP-X71 regression: after the internal cash upgrade, direct
/// transfers ("donations") to a market move neither cash, exchange rate,
/// supply-cap headroom, nor any account's borrowing power.
contract InternalCashLiveSystemTest is PostProposalCheck {
    address donor = address(0xD0D0);
    address attacker = address(0xA77AC);

    function _donate(MToken market, uint256 amount) internal {
        IERC20 underlying = IERC20(MErc20(address(market)).underlying());
        deal(address(underlying), donor, amount);
        vm.prank(donor);
        underlying.transfer(address(market), amount);
    }

    function _assertDonationInert(string memory marketName) internal {
        MToken market = MToken(addresses.getAddress(marketName));
        IERC20 underlying = IERC20(MErc20(address(market)).underlying());

        market.accrueInterest();
        uint256 cash = market.getCash();
        uint256 rate = market.exchangeRateStored();
        uint256 balance = underlying.balanceOf(address(market));

        assertEq(
            MErc20Delegate(address(market)).internalCash(),
            balance,
            "internalCash not synced at upgrade"
        );

        uint256 donation = cash + 1_000 * 10 ** 6;
        _donate(market, donation);

        assertEq(market.getCash(), cash, "donation moved getCash");
        assertEq(market.exchangeRateStored(), rate, "donation moved rate");
        assertEq(underlying.balanceOf(address(market)), balance + donation);

        /// admin can recover exactly the donation, nothing more
        address admin = market.admin();
        uint256 adminBefore = underlying.balanceOf(admin);
        vm.prank(admin);
        MErc20Delegate(address(market))._sweepExcessCash();
        assertEq(underlying.balanceOf(admin) - adminBefore, donation);
        assertEq(underlying.balanceOf(address(market)), balance);
        assertEq(market.getCash(), cash);
    }

    function testDonationInertBaseUSDC() public {
        vm.selectFork(BASE_FORK_ID);
        _assertDonationInert("MOONWELL_USDC");
    }

    function testDonationInertOptimismUSDC() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        _assertDonationInert("MOONWELL_USDC");
    }

    function testDonationInertEthereumUSDC() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        _assertDonationInert("MOONWELL_USDC");
    }

    /// @notice the Venus THE pattern: fill a capped market, then donate to grow
    /// collateral past the cap. Must be a no-op after MIP-X71.
    function testDonationCannotBypassSupplyCap() public {
        vm.selectFork(BASE_FORK_ID);

        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        MToken market = MToken(addresses.getAddress("MOONWELL_VIRTUAL"));
        IERC20 underlying = IERC20(MErc20(address(market)).underlying());

        market.accrueInterest();
        uint256 supplies = market.getCash() +
            market.totalBorrows() -
            market.totalReserves();

        /// known headroom, independent of live cap usage
        uint256 cap = supplies + 1_000_000e18;
        MToken[] memory capMarkets = new MToken[](1);
        capMarkets[0] = market;
        uint256[] memory caps = new uint256[](1);
        caps[0] = cap;
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        comptroller._setMarketSupplyCaps(capMarkets, caps);

        uint256 fill = cap - supplies - 1e18;
        deal(address(underlying), attacker, fill);
        vm.startPrank(attacker);
        underlying.approve(address(market), fill);
        assertEq(MErc20(address(market)).mint(fill), 0, "fill mint failed");
        address[] memory markets = new address[](1);
        markets[0] = address(market);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        (, uint256 liquidityBefore, ) = comptroller.getAccountLiquidity(
            attacker
        );
        uint256 cashBefore = market.getCash();

        deal(address(underlying), attacker, cap);
        vm.prank(attacker);
        underlying.transfer(address(market), cap);

        (, uint256 liquidityAfter, ) = comptroller.getAccountLiquidity(
            attacker
        );
        assertEq(liquidityAfter, liquidityBefore, "donation grew collateral");
        assertEq(market.getCash(), cashBefore, "donation moved cash");
        assertLt(
            market.getCash() + market.totalBorrows() - market.totalReserves(),
            cap,
            "supplies exceed cap"
        );
    }

    /// @notice Base MOONWELL_WETH is administered by MWETH_OWNER_WRAPPER;
    /// MIP-X71 upgrades the wrapper so governance can sweep through it
    function testSweepBaseMWethThroughWrapper() public {
        vm.selectFork(BASE_FORK_ID);

        MToken market = MToken(addresses.getAddress("MOONWELL_WETH"));
        IERC20 weth = IERC20(addresses.getAddress("WETH"));
        MWethOwnerWrapper wrapper = MWethOwnerWrapper(
            payable(addresses.getAddress("MWETH_OWNER_WRAPPER"))
        );
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        assertEq(market.admin(), address(wrapper), "wrapper not admin");

        uint256 cash = market.getCash();
        uint256 donation = 5 ether;
        _donate(market, donation);

        uint256 wrapperBefore = weth.balanceOf(address(wrapper));
        vm.prank(temporalGovernor);
        wrapper._sweepExcessCash();
        assertEq(weth.balanceOf(address(wrapper)) - wrapperBefore, donation);
        assertEq(market.getCash(), cash, "sweep moved cash");

        address recipient = address(0xFEE);
        vm.prank(temporalGovernor);
        wrapper.withdrawToken(address(weth), recipient, donation);
        assertEq(weth.balanceOf(recipient), donation);
    }

    /// @notice MWethDelegate overrides doTransferOut (ETH unwrap path) and must
    /// still debit internalCash
    function testMWethRedeemTracksInternalCashBase() public {
        vm.selectFork(BASE_FORK_ID);
        _assertMWethRoundTrip();
    }

    function testMWethRedeemTracksInternalCashOptimism() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        _assertMWethRoundTrip();
    }

    function testMWethRedeemTracksInternalCashEthereum() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        _assertMWethRoundTrip();
    }

    function _assertMWethRoundTrip() internal {
        MToken market = MToken(addresses.getAddress("MOONWELL_WETH"));
        IERC20 weth = IERC20(addresses.getAddress("WETH"));
        address user = address(0xE7E7);
        uint256 amount = 10 ether;

        market.accrueInterest();
        uint256 cashBefore = market.getCash();

        deal(address(weth), user, amount);
        vm.startPrank(user);
        weth.approve(address(market), amount);
        assertEq(MErc20(address(market)).mint(amount), 0, "mint failed");
        assertEq(market.getCash(), cashBefore + amount, "mint not tracked");

        uint256 ethBefore = user.balance;
        assertEq(
            MErc20(address(market)).redeemUnderlying(amount / 2),
            0,
            "redeem failed"
        );
        vm.stopPrank();

        assertEq(user.balance - ethBefore, amount / 2, "ETH not received");
        assertEq(
            market.getCash(),
            cashBefore + amount / 2,
            "redeem not tracked"
        );
        assertEq(
            MErc20Delegate(address(market)).internalCash(),
            weth.balanceOf(address(market)),
            "internalCash drifted from WETH balance"
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@utils/ChainIds.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MarketStateGuard} from "@test/utils/MarketStateGuard.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

/// @notice Proves the pending proposals (every id:0 MIP and every pending
/// MultichainGovernorV2 proposal) leave each market on every chain unchanged
/// and usable, except what a proposal declares via expectedPriceChanges()
/// (prices, Morpho oracles) or expectedMarketStateChanges() (risk, accounting,
/// per chain). Markets listed by a pending proposal must be wired and usable.
contract ProposalMarketInvarianceIntegrationTest is PostProposalCheck {
    using ChainIds for uint256;

    /// @notice USD value (18 decimals) supplied per market; half of it is borrowed.
    uint256 internal constant EXERCISE_USD = 100e18;

    /// @notice USD value (18 decimals) of WETH posted as collateral.
    uint256 internal constant COLLATERAL_USD = 100_000e18;

    /// @notice relative drift allowed on Morpho oracle prices, same as MarketPriceGuard.
    uint256 internal constant MAX_DRIFT = 0.01e18;

    function _beforePendingProposals() internal override {
        uint256 activeFork = vm.activeFork();
        for (uint256 i = MOONBEAM_FORK_ID; i <= ETHEREUM_FORK_ID; i++) {
            stateGuard.snapshot(addresses, i);
        }
        vm.selectFork(activeFork);
    }

    /// @notice Comptroller-level and per-market risk parameters are untouched.
    function testRiskParametersUnchanged() public {
        uint256 chains;
        for (uint256 f = MOONBEAM_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            if (!stateGuard.snapshotTaken(f)) continue;
            vm.selectFork(f);
            chains++;
            Comptroller comptroller = _comptroller();
            string memory chain = vm.toString(block.chainid);

            if (!_declared(address(comptroller), true)) {
                _assertComptrollerUnchanged(
                    stateGuard.comptrollerBefore(f),
                    stateGuard.readComptroller(comptroller),
                    chain
                );
            }

            address[] memory markets = stateGuard.marketsBefore(f);
            for (uint256 i = 0; i < markets.length; i++) {
                if (_declared(markets[i], true)) continue;
                MarketStateGuard.MarketState memory b = stateGuard.marketBefore(
                    f,
                    markets[i]
                );
                MarketStateGuard.MarketState memory a = stateGuard.readMarket(
                    comptroller,
                    MToken(markets[i])
                );
                string memory label = _label(markets[i]);

                assertEq(
                    a.isListed,
                    b.isListed,
                    string.concat("isListed ", label)
                );
                assertEq(
                    a.collateralFactor,
                    b.collateralFactor,
                    string.concat("collateralFactor ", label)
                );
                assertEq(
                    a.supplyCap,
                    b.supplyCap,
                    string.concat("supplyCap ", label)
                );
                assertEq(
                    a.borrowCap,
                    b.borrowCap,
                    string.concat("borrowCap ", label)
                );
                assertEq(
                    a.mintPaused,
                    b.mintPaused,
                    string.concat("mintPaused ", label)
                );
                assertEq(
                    a.borrowPaused,
                    b.borrowPaused,
                    string.concat("borrowPaused ", label)
                );
                assertEq(
                    a.reserveFactor,
                    b.reserveFactor,
                    string.concat("reserveFactor ", label)
                );
                assertEq(
                    a.interestRateModel,
                    b.interestRateModel,
                    string.concat("interestRateModel ", label)
                );
                assertEq(a.admin, b.admin, string.concat("admin ", label));
                assertEq(
                    a.comptroller,
                    b.comptroller,
                    string.concat("comptroller ", label)
                );
            }

            _assertNewMarketsWired(f, comptroller);
        }
        assertGt(chains, 0, "no chain snapshotted");
    }

    /// @notice Stored accounting is bit-identical: no undeclared proposal moves
    /// funds, mints shares or accrues interest on a market.
    function testMarketAccountingUnchanged() public {
        uint256 checked;
        for (uint256 f = MOONBEAM_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            if (!stateGuard.snapshotTaken(f)) continue;
            vm.selectFork(f);
            Comptroller comptroller = _comptroller();
            address[] memory markets = stateGuard.marketsBefore(f);

            for (uint256 i = 0; i < markets.length; i++) {
                if (_declared(markets[i], false)) continue;
                checked++;
                MarketStateGuard.MarketState memory b = stateGuard.marketBefore(
                    f,
                    markets[i]
                );
                MarketStateGuard.MarketState memory a = stateGuard.readMarket(
                    comptroller,
                    MToken(markets[i])
                );
                string memory label = _label(markets[i]);

                assertEq(
                    a.totalSupply,
                    b.totalSupply,
                    string.concat("totalSupply ", label)
                );
                assertEq(
                    a.totalBorrows,
                    b.totalBorrows,
                    string.concat("totalBorrows ", label)
                );
                assertEq(
                    a.totalReserves,
                    b.totalReserves,
                    string.concat("totalReserves ", label)
                );
                assertEq(a.cash, b.cash, string.concat("cash ", label));
                assertEq(
                    a.exchangeRate,
                    b.exchangeRate,
                    string.concat("exchangeRate ", label)
                );
                assertEq(
                    a.borrowIndex,
                    b.borrowIndex,
                    string.concat("borrowIndex ", label)
                );
                assertEq(
                    a.accrualTimestamp,
                    b.accrualTimestamp,
                    string.concat("accrualTimestamp ", label)
                );
            }
        }
        assertGt(checked, 0, "no market checked");
    }

    /// @notice Every registered Morpho Blue oracle (MORPHO_CHAINLINK_*_ORACLE)
    /// prices within 1% of its pre-proposal price unless declared in
    /// expectedPriceChanges().
    function testMorphoBlueOraclePricesPreserved() public {
        uint256 checked;
        for (uint256 f = MOONBEAM_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            if (!stateGuard.snapshotTaken(f)) continue;
            vm.selectFork(f);
            address[] memory oracles = stateGuard.morphoOraclesBefore(f);

            for (uint256 i = 0; i < oracles.length; i++) {
                if (_contains(_priceChangeAllowlist, oracles[i])) continue;
                checked++;
                uint256 before = stateGuard.morphoPriceBefore(f, oracles[i]);
                uint256 after_ = stateGuard.readMorphoPrice(oracles[i]);
                if (!_withinDrift(before, after_)) {
                    // OEV round selection depends on block.timestamp; re-read at snapshot time
                    uint256 now_ = block.timestamp;
                    vm.warp(stateGuard.snapshotTimestamp(f));
                    after_ = stateGuard.readMorphoPrice(oracles[i]);
                    vm.warp(now_);
                }
                assertTrue(
                    _withinDrift(before, after_),
                    string.concat(
                        "Morpho oracle price moved on ",
                        vm.toString(block.chainid),
                        ": ",
                        vm.toString(oracles[i]),
                        " before ",
                        vm.toString(before),
                        " after ",
                        vm.toString(after_)
                    )
                );
            }
        }
        assertGt(checked, 0, "no Morpho oracle checked");
    }

    /// @notice No proposal routes a market through a registry entry marked
    /// retired (any *DEPRECATED* name, or a Chainlink *_SVR proxy), directly,
    /// as a wrapper's priceFeed(), or as a composite's base(). Markets already
    /// priced that way before the proposals are logged, not failed.
    function testNoMarketRoutedThroughRetiredFeed() public {
        uint256 checked;
        for (uint256 f = MOONBEAM_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            if (!stateGuard.snapshotTaken(f)) continue;
            vm.selectFork(f);
            address[] memory retired = stateGuard.retiredOf(block.chainid);
            Comptroller comptroller = _comptroller();
            MToken[] memory markets = comptroller.getAllMarkets();

            for (uint256 i = 0; i < markets.length; i++) {
                (address feed, address inner) = stateGuard.resolveFeeds(
                    address(comptroller.oracle()),
                    address(markets[i])
                );
                if (feed == address(0)) continue;
                checked++;
                if (
                    !_contains(retired, feed) &&
                    !(inner != address(0) && _contains(retired, inner))
                ) {
                    continue;
                }

                MarketStateGuard.MarketState memory b = stateGuard.marketBefore(
                    f,
                    address(markets[i])
                );
                string memory label = _label(address(markets[i]));
                assertTrue(
                    b.feed == feed && b.innerFeed == inner,
                    string.concat(
                        "proposal routed market through a retired feed: ",
                        label
                    )
                );
                console.log(
                    "pre-existing: market priced through a retired feed:",
                    label
                );
            }
        }
        assertGt(checked, 0, "no market feed resolved");
    }

    /// @notice Every market stays usable: with WETH collateral and every priced
    /// market entered (so each borrow re-prices them all), supply, borrow,
    /// repay and redeem a small amount of every market not paused.
    function testEveryMarketBorrowSupplyRedeemRepay() public {
        uint256 chains;
        for (uint256 f = BASE_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            if (!stateGuard.snapshotTaken(f)) continue;
            vm.selectFork(f);
            if (!addresses.isAddressSet("MOONWELL_WETH")) continue;
            _exerciseChain(f);
            chains++;
        }
        assertGt(chains, 0, "no chain exercised");
    }

    function _exerciseChain(uint256 forkId) internal {
        Comptroller comptroller = _comptroller();
        PriceOracle oracle = comptroller.oracle();
        MToken[] memory markets = comptroller.getAllMarkets();
        string memory chain = vm.toString(block.chainid);
        address user = makeAddr(string.concat("invariance-user-", chain));

        _postWethCollateral(user, oracle);

        // enter every market priced before the proposals: losing a price is a regression
        address[] memory toEnter = new address[](markets.length);
        uint256 entered;
        for (uint256 i = 0; i < markets.length; i++) {
            MarketStateGuard.MarketState memory b = stateGuard.marketBefore(
                forkId,
                address(markets[i])
            );
            // listed by a pending proposal: no baseline, so it must price now
            if (!b.isListed) {
                assertGt(
                    _readPrice(oracle, markets[i]),
                    0,
                    string.concat(
                        "new market is unpriced: ",
                        _label(address(markets[i]))
                    )
                );
                toEnter[entered++] = address(markets[i]);
                continue;
            }
            if (!b.priced) {
                continue;
            }
            if (_readPrice(oracle, markets[i]) == 0) {
                // a staleness bound tripped by the governance warp is not a
                // feed change; it must still price at the snapshot time
                uint256 now_ = block.timestamp;
                vm.warp(stateGuard.snapshotTimestamp(forkId));
                uint256 atSnapshot = _readPrice(oracle, markets[i]);
                vm.warp(now_);
                assertGt(
                    atSnapshot,
                    0,
                    string.concat(
                        "market lost its price: ",
                        _label(address(markets[i]))
                    )
                );
                console.log("skip (stale after warp):", markets[i].symbol());
                continue;
            }
            toEnter[entered++] = address(markets[i]);
        }
        assembly {
            mstore(toEnter, entered)
        }
        vm.prank(user);
        comptroller.enterMarkets(toEnter);

        _liftCaps(comptroller, toEnter);

        string memory unexercised;
        uint256 exercised;
        for (uint256 i = 0; i < toEnter.length; i++) {
            MErc20 market = MErc20(toEnter[i]);
            if (
                comptroller.mintGuardianPaused(address(market)) &&
                comptroller.borrowGuardianPaused(address(market))
            ) {
                console.log("skip (mint and borrow paused):", market.symbol());
                continue;
            }
            if (_exerciseMarket(comptroller, oracle, market, user)) {
                exercised++;
            } else {
                unexercised = string.concat(unexercised, market.symbol(), " ");
            }
        }
        console.log(
            string.concat(
                "chain ",
                chain,
                ": exercised ",
                vm.toString(exercised),
                " of ",
                vm.toString(toEnter.length),
                " markets"
            )
        );
        assertGt(exercised, 0, string.concat("no market exercised on ", chain));
        assertEq(
            bytes(unexercised).length,
            0,
            string.concat("markets not exercised on ", chain, ": ", unexercised)
        );

        // every entered market is re-priced by the liquidity check
        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(user);
        assertEq(err, 0, string.concat("liquidity error on ", chain));
        assertGt(liquidity, 0, string.concat("no liquidity on ", chain));
        assertEq(shortfall, 0, string.concat("shortfall on ", chain));
    }

    /// @notice caps are policy, not pricing: lift them so the price path is
    /// exercised even where governance froze a market (Base borrowCap == 1)
    function _liftCaps(
        Comptroller comptroller,
        address[] memory list
    ) internal {
        MToken[] memory mTokens = new MToken[](list.length);
        for (uint256 i = 0; i < list.length; i++) {
            mTokens[i] = MToken(list[i]);
        }
        uint256[] memory unlimited = new uint256[](list.length);
        address admin = comptroller.admin();
        vm.startPrank(admin);
        comptroller._setMarketBorrowCaps(mTokens, unlimited);
        comptroller._setMarketSupplyCaps(mTokens, unlimited);
        vm.stopPrank();
    }

    /// @notice supply, borrow, repay and redeem ~EXERCISE_USD of `market`;
    /// a leg runs unless the market pauses it
    /// @return false when neither leg could run (no funding source)
    function _exerciseMarket(
        Comptroller comptroller,
        PriceOracle oracle,
        MErc20 market,
        address user
    ) internal returns (bool) {
        string memory label = _label(address(market));
        uint256 amount = (EXERCISE_USD * 1e18) /
            oracle.getUnderlyingPrice(market);
        assertGt(amount, 0, string.concat("zero sized amount: ", label));
        address underlying = market.underlying();

        bool supplied;
        if (!comptroller.mintGuardianPaused(address(market))) {
            try this.dealExternal(underlying, user, amount) {
                vm.startPrank(user);
                _approve(underlying, address(market), amount);
                assertEq(
                    market.mint(amount),
                    0,
                    string.concat("mint failed: ", label)
                );
                vm.stopPrank();
                supplied = true;
            } catch {
                console.log(
                    "no deal for underlying, supply leg skipped:",
                    label
                );
            }
        }

        bool borrowed;
        uint256 borrowAmount = amount / 2;
        if (
            !comptroller.borrowGuardianPaused(address(market)) &&
            market.getCash() >= borrowAmount
        ) {
            uint256 balanceBefore = EIP20Interface(underlying).balanceOf(user);
            uint256 nativeBefore = user.balance;
            vm.startPrank(user);
            assertEq(
                market.borrow(borrowAmount),
                0,
                string.concat("borrow failed: ", label)
            );
            // MWethDelegate pays WETH borrows out as native ETH; re-wrap to repay
            uint256 native = user.balance - nativeBefore;
            if (native > 0) {
                (bool ok, ) = underlying.call{value: native}(
                    abi.encodeWithSignature("deposit()")
                );
                require(ok, "WETH deposit failed");
            }
            assertEq(
                EIP20Interface(underlying).balanceOf(user) - balanceBefore,
                borrowAmount,
                string.concat("borrow did not pay out: ", label)
            );
            _approve(underlying, address(market), type(uint256).max);
            assertEq(
                market.repayBorrow(type(uint256).max),
                0,
                string.concat("repay failed: ", label)
            );
            vm.stopPrank();
            assertEq(
                market.borrowBalanceStored(user),
                0,
                string.concat("debt left: ", label)
            );
            borrowed = true;
        }

        if (supplied) {
            vm.prank(user);
            assertEq(
                market.redeemUnderlying(amount),
                0,
                string.concat("redeem failed: ", label)
            );
        }

        if (!supplied && !borrowed) {
            console.log("not exercised (no supply source, no cash):", label);
        }
        return supplied || borrowed;
    }

    /// @notice external so a token deal() cannot fit (non-standard storage) is catchable
    function dealExternal(address token, address to, uint256 amount) external {
        require(msg.sender == address(this), "only self");
        deal(token, to, amount);
    }

    function _postWethCollateral(address user, PriceOracle oracle) internal {
        MErc20 mWeth = MErc20(addresses.getAddress("MOONWELL_WETH"));
        uint256 amount = (COLLATERAL_USD * 1e18) /
            oracle.getUnderlyingPrice(mWeth);
        address weth = mWeth.underlying();

        deal(weth, user, amount);
        vm.startPrank(user);
        _approve(weth, address(mWeth), amount);
        assertEq(mWeth.mint(amount), 0, "WETH collateral mint failed");
        vm.stopPrank();
    }

    /// @notice approve via low-level call: USDT-style tokens return no bool
    function _approve(address token, address spender, uint256 amount) internal {
        (bool ok, ) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, 0)
        );
        require(ok, "approve reset failed");
        (ok, ) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, amount)
        );
        require(ok, "approve failed");
    }

    /// @notice markets listed by a pending proposal have no baseline to diff;
    /// they must at least be listed on, and point back at, this Comptroller
    function _assertNewMarketsWired(
        uint256 forkId,
        Comptroller comptroller
    ) internal {
        MToken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            if (stateGuard.marketBefore(forkId, address(markets[i])).isListed) {
                continue;
            }
            MarketStateGuard.MarketState memory a = stateGuard.readMarket(
                comptroller,
                markets[i]
            );
            string memory label = _label(address(markets[i]));
            assertTrue(
                a.isListed,
                string.concat("new market not listed ", label)
            );
            assertEq(
                a.comptroller,
                address(comptroller),
                string.concat("new market comptroller ", label)
            );
            console.log("new market wired:", label);
        }
    }

    function _assertComptrollerUnchanged(
        MarketStateGuard.ComptrollerState memory b,
        MarketStateGuard.ComptrollerState memory a,
        string memory chain
    ) internal {
        assertEq(a.oracle, b.oracle, string.concat("oracle ", chain));
        assertEq(
            a.closeFactor,
            b.closeFactor,
            string.concat("closeFactor ", chain)
        );
        assertEq(
            a.liquidationIncentive,
            b.liquidationIncentive,
            string.concat("liquidationIncentive ", chain)
        );
        assertEq(
            a.pauseGuardian,
            b.pauseGuardian,
            string.concat("pauseGuardian ", chain)
        );
        assertEq(
            a.borrowCapGuardian,
            b.borrowCapGuardian,
            string.concat("borrowCapGuardian ", chain)
        );
        assertEq(
            a.supplyCapGuardian,
            b.supplyCapGuardian,
            string.concat("supplyCapGuardian ", chain)
        );
        assertEq(
            a.transferPaused,
            b.transferPaused,
            string.concat("transferPaused ", chain)
        );
        assertEq(
            a.seizePaused,
            b.seizePaused,
            string.concat("seizePaused ", chain)
        );
        assertEq(
            a.implementation,
            b.implementation,
            string.concat("implementation ", chain)
        );
    }

    function _readPrice(
        PriceOracle oracle,
        MToken market
    ) internal view returns (uint256) {
        try oracle.getUnderlyingPrice(market) returns (uint256 p) {
            return p;
        } catch {
            return 0;
        }
    }

    function _comptroller() internal view returns (Comptroller) {
        return Comptroller(addresses.getAddress("UNITROLLER"));
    }

    /// @notice true when a proposal declared `target` on this chain for the
    /// given kind of change (risk parameters, else stored accounting)
    function _declared(address target, bool risk) internal view returns (bool) {
        for (uint256 i = 0; i < _marketStateChanges.length; i++) {
            Proposal.MarketStateChange memory c = _marketStateChanges[i];
            if (
                c.chainId == block.chainid &&
                c.target == target &&
                (risk ? c.riskParameters : c.accounting)
            ) {
                return true;
            }
        }
        return false;
    }

    function _label(address market) internal view returns (string memory) {
        return
            string.concat(
                MToken(market).symbol(),
                " ",
                vm.toString(block.chainid)
            );
    }

    function _withinDrift(uint256 a, uint256 b) internal pure returns (bool) {
        if (a == 0 || b == 0) return false;
        uint256 diff = a > b ? a - b : b - a;
        return (diff * 1e18) / a <= MAX_DRIFT;
    }

    function _contains(
        address[] memory list,
        address item
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < list.length; i++) {
            if (list[i] == item) return true;
        }
        return false;
    }
}

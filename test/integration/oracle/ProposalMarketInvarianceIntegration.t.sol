// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@utils/ChainIds.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {PriceOracle} from "@protocol/oracles/PriceOracle.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MarketPriceGuard} from "@test/utils/MarketPriceGuard.sol";

/// @notice Morpho Blue oracle surface (MorphoChainlinkOracleV2).
interface IMorphoChainlinkOracle {
    function price() external view returns (uint256);

    function BASE_FEED_1() external view returns (address);
}

/// @notice Runs ONE oracle proposal (MIP-X72 by default) on fresh Base,
/// Optimism and Ethereum forks, with a full snapshot of every market taken
/// before it, and proves the markets come out unchanged and usable.
/// Override the target with INVARIANCE_MIP_PATH / INVARIANCE_MIP_ENVPATH.
contract ProposalMarketInvarianceIntegrationTest is
    Test,
    ChainlinkOracleConfigs
{
    using ChainIds for uint256;

    struct MarketState {
        bool isListed;
        uint256 collateralFactor;
        uint256 supplyCap;
        uint256 borrowCap;
        bool mintPaused;
        bool borrowPaused;
        uint256 reserveFactor;
        address interestRateModel;
        address admin;
        address comptroller;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 cash;
        uint256 exchangeRate;
        uint256 borrowIndex;
        uint256 accrualTimestamp;
    }

    struct ComptrollerState {
        address oracle;
        uint256 closeFactor;
        uint256 liquidationIncentive;
        address pauseGuardian;
        address borrowCapGuardian;
        address supplyCapGuardian;
        bool transferPaused;
        bool seizePaused;
        address implementation;
        uint256 marketCount;
    }

    string internal constant DEFAULT_PATH =
        "artifacts/foundry/mip-x72.sol/mipx72.json";
    string internal constant DEFAULT_ENVPATH = "proposals/mips/mip-x72/x72.sh";

    /// @notice USD value (18 decimals) supplied per market; half of it is borrowed.
    uint256 internal constant BORROW_USD = 100e18;

    /// @notice USD value (18 decimals) of WETH posted as collateral.
    uint256 internal constant COLLATERAL_USD = 100_000e18;

    uint256[3] internal FORKS = [
        BASE_FORK_ID,
        OPTIMISM_FORK_ID,
        ETHEREUM_FORK_ID
    ];

    Addresses public addresses;
    MarketPriceGuard public priceGuard;

    mapping(uint256 => ComptrollerState) internal _comptrollerBefore;
    mapping(uint256 => address[]) internal _marketsBefore;
    mapping(uint256 => mapping(address => MarketState)) internal _marketBefore;
    mapping(string => uint256) internal _morphoPriceBefore;
    uint256 internal _morphoSnapshotTimestamp;

    function setUp() public {
        ETHEREUM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        priceGuard = new MarketPriceGuard();
        vm.makePersistent(address(priceGuard));

        for (uint256 i = 0; i < FORKS.length; i++) {
            _snapshotChain(FORKS[i]);
            priceGuard.snapshot(addresses, FORKS[i]);
        }
        _snapshotMorphoOracles();

        _runProposal();

        addresses.removeAllRestrictions();
    }

    /// @notice Comptroller-level and per-market risk parameters are untouched.
    function testRiskParametersUnchanged() public {
        for (uint256 f = 0; f < FORKS.length; f++) {
            vm.selectFork(FORKS[f]);
            Comptroller comptroller = _comptroller();

            ComptrollerState memory before = _comptrollerBefore[FORKS[f]];
            ComptrollerState memory now_ = _readComptroller(comptroller);
            string memory chain = vm.toString(block.chainid);

            assertEq(
                now_.oracle,
                before.oracle,
                string.concat("oracle ", chain)
            );
            assertEq(
                now_.closeFactor,
                before.closeFactor,
                string.concat("closeFactor ", chain)
            );
            assertEq(
                now_.liquidationIncentive,
                before.liquidationIncentive,
                string.concat("liquidationIncentive ", chain)
            );
            assertEq(
                now_.pauseGuardian,
                before.pauseGuardian,
                string.concat("pauseGuardian ", chain)
            );
            assertEq(
                now_.borrowCapGuardian,
                before.borrowCapGuardian,
                string.concat("borrowCapGuardian ", chain)
            );
            assertEq(
                now_.supplyCapGuardian,
                before.supplyCapGuardian,
                string.concat("supplyCapGuardian ", chain)
            );
            assertEq(
                now_.transferPaused,
                before.transferPaused,
                string.concat("transferPaused ", chain)
            );
            assertEq(
                now_.seizePaused,
                before.seizePaused,
                string.concat("seizePaused ", chain)
            );
            assertEq(
                now_.implementation,
                before.implementation,
                string.concat("implementation ", chain)
            );
            assertEq(
                now_.marketCount,
                before.marketCount,
                string.concat("market count ", chain)
            );

            address[] memory markets = _marketsBefore[FORKS[f]];
            assertGt(
                markets.length,
                0,
                string.concat("no markets snapshotted ", chain)
            );
            for (uint256 i = 0; i < markets.length; i++) {
                MarketState memory b = _marketBefore[FORKS[f]][markets[i]];
                MarketState memory a = _readMarket(
                    comptroller,
                    MToken(markets[i])
                );
                string memory label = string.concat(
                    MToken(markets[i]).symbol(),
                    " ",
                    chain
                );

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
        }
    }

    /// @notice Stored market accounting is bit-identical: the proposal moves no
    /// funds, mints no shares and accrues no interest on any market.
    function testMarketAccountingUnchanged() public {
        for (uint256 f = 0; f < FORKS.length; f++) {
            vm.selectFork(FORKS[f]);
            Comptroller comptroller = _comptroller();
            address[] memory markets = _marketsBefore[FORKS[f]];

            for (uint256 i = 0; i < markets.length; i++) {
                MarketState memory b = _marketBefore[FORKS[f]][markets[i]];
                MarketState memory a = _readMarket(
                    comptroller,
                    MToken(markets[i])
                );
                string memory label = string.concat(
                    MToken(markets[i]).symbol(),
                    " ",
                    vm.toString(block.chainid)
                );

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
    }

    /// @notice Every Comptroller market price stays within 1% (MarketPriceGuard,
    /// empty allowlist: this proposal declares no intended price change).
    function testComptrollerPricesPreserved() public {
        uint256 guarded;
        for (uint256 f = 0; f < FORKS.length; f++) {
            assertTrue(
                priceGuard.snapshotTaken(FORKS[f]),
                "price snapshot missing"
            );
            MarketPriceGuard.Violation[] memory violations = priceGuard.check(
                addresses,
                FORKS[f],
                new address[](0)
            );
            assertEq(violations.length, 0, priceGuard.describe(violations));
            guarded++;
        }
        assertEq(guarded, FORKS.length, "not every chain guarded");
    }

    /// @notice Every Base Morpho Blue oracle reading an upgraded wrapper prices
    /// the market within 1% of its pre-proposal price.
    function testMorphoBlueOraclePricesPreserved() public {
        vm.selectFork(BASE_FORK_ID);
        MorphoOracleConfig[] memory configs = getMorphoOracleConfigurations(
            block.chainid
        );
        assertGt(configs.length, 0, "no Morpho wrappers configured");

        for (uint256 i = 0; i < configs.length; i++) {
            string memory key = _morphoOracleKey(configs[i].proxyName);
            IMorphoChainlinkOracle oracle = IMorphoChainlinkOracle(
                addresses.getAddress(key)
            );

            // the upgraded proxy must be on the price path, else this is vacuous
            assertEq(
                oracle.BASE_FEED_1(),
                addresses.getAddress(
                    string.concat(configs[i].proxyName, "_ORACLE_PROXY")
                ),
                string.concat("upgraded wrapper not on price path of ", key)
            );

            uint256 before = _morphoPriceBefore[key];
            assertGt(
                before,
                0,
                string.concat("no pre-proposal price for ", key)
            );

            uint256 after_ = oracle.price();
            if (!_withinOnePercent(before, after_)) {
                // round selection depends on block.timestamp; re-read at snapshot time
                uint256 now_ = block.timestamp;
                vm.warp(_morphoSnapshotTimestamp);
                after_ = oracle.price();
                vm.warp(now_);
            }
            assertApproxEqRel(
                after_,
                before,
                0.01e18,
                string.concat("Morpho oracle price moved for ", key)
            );
        }
    }

    /// @notice No listed market is priced through a feed the proposal retired:
    /// an archived (_DEPRECATED_V4 / _DEPRECATED_SVR) oracle or an SVR proxy,
    /// whether used directly, as a wrapper's priceFeed, or as a composite base.
    function testNoMarketPricedThroughRetiredFeed() public {
        uint256 checked;
        for (uint256 f = 0; f < FORKS.length; f++) {
            vm.selectFork(FORKS[f]);
            address[] memory retired = _retiredFeeds(block.chainid);
            ChainlinkOracle oracle = ChainlinkOracle(
                address(_comptroller().oracle())
            );
            MToken[] memory markets = _comptroller().getAllMarkets();

            for (uint256 i = 0; i < markets.length; i++) {
                address feed = _feedOf(oracle, markets[i]);
                if (feed == address(0)) {
                    continue;
                }
                checked++;
                string memory label = string.concat(
                    markets[i].symbol(),
                    " ",
                    vm.toString(block.chainid)
                );

                assertFalse(
                    _contains(retired, feed),
                    string.concat("market feed is retired: ", label)
                );
                address inner = _innerFeed(feed);
                assertFalse(
                    inner != address(0) && _contains(retired, inner),
                    string.concat("market feed wraps a retired feed: ", label)
                );
            }
        }
        assertGt(checked, 0, "no market feed resolved");
    }

    /// @notice Every market stays usable: with WETH collateral and every priced
    /// market entered (so each borrow re-prices them all), supply, borrow,
    /// repay and redeem a small amount of every market not paused.
    function testEveryMarketBorrowSupplyRedeemRepay() public {
        for (uint256 f = 0; f < FORKS.length; f++) {
            vm.selectFork(FORKS[f]);
            _exerciseChain();
        }
    }

    function _exerciseChain() internal {
        Comptroller comptroller = _comptroller();
        PriceOracle oracle = comptroller.oracle();
        MToken[] memory markets = comptroller.getAllMarkets();
        address user = makeAddr(
            string.concat("invariance-user-", vm.toString(block.chainid))
        );
        string memory chain = vm.toString(block.chainid);

        _postWethCollateral(user, oracle);

        // enter every market priced before the proposal: a revert now is a regression
        address[] memory toEnter = new address[](markets.length);
        uint256 entered;
        for (uint256 i = 0; i < markets.length; i++) {
            if (!_wasPriced(address(markets[i]))) {
                continue;
            }
            if (_readPrice(oracle, markets[i]) == 0) {
                // a staleness bound tripped by the governance warp is not a
                // feed change; it must still price at the snapshot time
                uint256 now_ = block.timestamp;
                vm.warp(_snapshotTimestamp[vm.activeFork()]);
                uint256 atSnapshot = _readPrice(oracle, markets[i]);
                vm.warp(now_);
                assertGt(
                    atSnapshot,
                    0,
                    string.concat(
                        "market lost its price: ",
                        markets[i].symbol(),
                        " ",
                        chain
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
        vm.startPrank(comptroller.admin());
        comptroller._setMarketBorrowCaps(mTokens, unlimited);
        comptroller._setMarketSupplyCaps(mTokens, unlimited);
        vm.stopPrank();
    }

    /// @notice supply, borrow, repay and redeem ~BORROW_USD of `market`;
    /// a leg runs unless the market pauses it
    /// @return false when neither leg could run (no funding source)
    function _exerciseMarket(
        Comptroller comptroller,
        PriceOracle oracle,
        MErc20 market,
        address user
    ) internal returns (bool) {
        string memory label = string.concat(
            market.symbol(),
            " ",
            vm.toString(block.chainid)
        );
        uint256 amount = (BORROW_USD * 1e18) /
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

    function _supplyRoom(
        Comptroller comptroller,
        MErc20 market
    ) internal view returns (uint256) {
        uint256 cap = comptroller.supplyCaps(address(market));
        if (cap == 0) {
            return type(uint256).max;
        }
        uint256 supplied = (market.totalSupply() *
            market.exchangeRateStored()) / 1e18;
        return cap > supplied + 1 ? cap - supplied - 1 : 0;
    }

    function _snapshotChain(uint256 forkId) internal {
        vm.selectFork(forkId);
        Comptroller comptroller = _comptroller();
        _comptrollerBefore[forkId] = _readComptroller(comptroller);
        _snapshotTimestamp[forkId] = block.timestamp;

        MToken[] memory markets = comptroller.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            _marketsBefore[forkId].push(address(markets[i]));
            _marketBefore[forkId][address(markets[i])] = _readMarket(
                comptroller,
                markets[i]
            );
            try comptroller.oracle().getUnderlyingPrice(markets[i]) returns (
                uint256 p
            ) {
                if (p > 0) _pricedBefore[address(markets[i])] = true;
            } catch {}
        }
    }

    mapping(address => bool) internal _pricedBefore;
    mapping(uint256 => uint256) internal _snapshotTimestamp;

    function _wasPriced(address market) internal view returns (bool) {
        return _pricedBefore[market];
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

    function _snapshotMorphoOracles() internal {
        vm.selectFork(BASE_FORK_ID);
        _morphoSnapshotTimestamp = block.timestamp;
        MorphoOracleConfig[] memory configs = getMorphoOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < configs.length; i++) {
            string memory key = _morphoOracleKey(configs[i].proxyName);
            _morphoPriceBefore[key] = IMorphoChainlinkOracle(
                addresses.getAddress(key)
            ).price();
        }
    }

    function _runProposal() internal {
        string memory path = vm.envOr("INVARIANCE_MIP_PATH", DEFAULT_PATH);
        string memory envPath = vm.envOr(
            "INVARIANCE_MIP_ENVPATH",
            DEFAULT_ENVPATH
        );
        string memory primaryForkBefore = vm.envOr(
            "PRIMARY_FORK_ID",
            string("")
        );

        ProposalMap proposalMap = new ProposalMap();
        vm.makePersistent(address(proposalMap));

        proposalMap.setEnv(envPath);
        proposalMap.runProposal(addresses, path, envPath);
        proposalMap.cleanEnv(envPath);

        // vm.setEnv is process-global: restore so later suites see the CI value
        vm.setEnv("PRIMARY_FORK_ID", primaryForkBefore);
    }

    function _readComptroller(
        Comptroller comptroller
    ) internal view returns (ComptrollerState memory s) {
        s.oracle = address(comptroller.oracle());
        s.closeFactor = comptroller.closeFactorMantissa();
        s.liquidationIncentive = comptroller.liquidationIncentiveMantissa();
        s.pauseGuardian = comptroller.pauseGuardian();
        s.borrowCapGuardian = comptroller.borrowCapGuardian();
        s.supplyCapGuardian = comptroller.supplyCapGuardian();
        s.transferPaused = comptroller.transferGuardianPaused();
        s.seizePaused = comptroller.seizeGuardianPaused();
        s.implementation = comptroller.comptrollerImplementation();
        s.marketCount = comptroller.getAllMarkets().length;
    }

    function _readMarket(
        Comptroller comptroller,
        MToken market
    ) internal view returns (MarketState memory s) {
        (s.isListed, s.collateralFactor) = comptroller.markets(address(market));
        s.supplyCap = comptroller.supplyCaps(address(market));
        s.borrowCap = comptroller.borrowCaps(address(market));
        s.mintPaused = comptroller.mintGuardianPaused(address(market));
        s.borrowPaused = comptroller.borrowGuardianPaused(address(market));
        s.reserveFactor = market.reserveFactorMantissa();
        s.interestRateModel = address(market.interestRateModel());
        s.admin = market.admin();
        s.comptroller = address(market.comptroller());
        s.totalSupply = market.totalSupply();
        s.totalBorrows = market.totalBorrows();
        s.totalReserves = market.totalReserves();
        s.cash = market.getCash();
        s.exchangeRate = market.exchangeRateStored();
        s.borrowIndex = market.borrowIndex();
        s.accrualTimestamp = market.accrualBlockTimestamp();
    }

    /// @notice addresses of every registry entry this chain marks as retired
    function _retiredFeeds(
        uint256 chainId
    ) internal view returns (address[] memory out) {
        string memory json = vm.readFile(
            string.concat("chains/", vm.toString(chainId), ".json")
        );
        string[] memory names = abi.decode(
            vm.parseJson(json, "$[*].name"),
            (string[])
        );
        address[] memory addrs = abi.decode(
            vm.parseJson(json, "$[*].addr"),
            (address[])
        );
        out = new address[](names.length);
        uint256 n;
        for (uint256 i = 0; i < names.length; i++) {
            if (
                _endsWith(names[i], "_DEPRECATED_V4") ||
                _endsWith(names[i], "_DEPRECATED_SVR") ||
                _endsWith(names[i], "_SVR")
            ) {
                out[n++] = addrs[i];
            }
        }
        assembly {
            mstore(out, n)
        }
    }

    /// @notice feed ChainlinkOracle resolves for a market; zero when priced by
    /// a direct override or the market has no ERC20 underlying
    function _feedOf(
        ChainlinkOracle oracle,
        MToken market
    ) internal view returns (address) {
        (bool ok, bytes memory ret) = address(market).staticcall(
            abi.encodeWithSignature("underlying()")
        );
        if (!ok || ret.length != 32) {
            return address(0);
        }
        address underlying = abi.decode(ret, (address));
        if (oracle.assetPrices(underlying) != 0) {
            return address(0);
        }
        return address(oracle.getFeed(EIP20Interface(underlying).symbol()));
    }

    /// @notice the feed an OEV wrapper (priceFeed) or composite (base) reads
    function _innerFeed(address feed) internal view returns (address) {
        (bool ok, bytes memory ret) = feed.staticcall(
            abi.encodeWithSignature("priceFeed()")
        );
        if (ok && ret.length == 32) {
            return abi.decode(ret, (address));
        }
        (ok, ret) = feed.staticcall(abi.encodeWithSignature("base()"));
        if (ok && ret.length == 32) {
            return abi.decode(ret, (address));
        }
        return address(0);
    }

    function _comptroller() internal view returns (Comptroller) {
        return Comptroller(addresses.getAddress("UNITROLLER"));
    }

    function _morphoOracleKey(
        string memory proxyName
    ) internal pure returns (string memory) {
        return string.concat("MORPHO_", proxyName, "_ORACLE");
    }

    function _withinOnePercent(
        uint256 a,
        uint256 b
    ) internal pure returns (bool) {
        uint256 diff = a > b ? a - b : b - a;
        return a != 0 && (diff * 1e18) / a <= 0.01e18;
    }

    function _endsWith(
        string memory s,
        string memory suffix
    ) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(suffix);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[a.length - b.length + i] != b[i]) return false;
        }
        return true;
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

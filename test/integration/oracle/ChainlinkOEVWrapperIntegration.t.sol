pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {LiquidationData, Liquidations, LiquidationState} from "@test/utils/Liquidations.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";

contract ChainlinkOEVWrapperIntegrationTest is
    PostProposalCheck,
    ChainlinkOracleConfigs,
    Liquidations
{
    event LiquidatorFeeBpsChanged(
        uint16 oldLiquidatorFeeBps,
        uint16 newLiquidatorFeeBps
    );
    event PriceUpdatedEarlyAndLiquidated(
        address indexed borrower,
        uint256 repayAmount,
        address mTokenCollateral,
        address mTokenLoan,
        uint256 protocolFee,
        uint256 liquidatorFee
    );

    // Array of wrappers to test, resolved from oracle configs
    ChainlinkOEVWrapper[] public wrappers;
    Comptroller comptroller;
    MarketBase public marketBase;
    OEVProtocolFeeRedeemer public redeemer;

    // Test actors
    address internal constant BORROWER =
        address(uint160(uint256(keccak256(abi.encodePacked("BORROWER")))));
    address internal constant LIQUIDATOR =
        address(uint160(uint256(keccak256(abi.encodePacked("LIQUIDATOR")))));

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");

        super.setUp();
        vm.selectFork(primaryForkId);
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);
        // Resolve wrappers from oracle configurations for the active chain
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < oracleConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(oracleConfigs[i].oracleName, "_OEV_WRAPPER")
            );
            if (addresses.isAddressSet(wrapperName)) {
                ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
                    payable(addresses.getAddress(wrapperName))
                );
                wrappers.push(wrapper);

                // Make wrapper persistent so it survives fork rolls
                vm.makePersistent(address(wrapper));
            }
        }

        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));
        vm.makePersistent(address(oracle));

        redeemer = OEVProtocolFeeRedeemer(
            payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
        );
        vm.makePersistent(address(redeemer));
    }

    function _perWrapperActor(
        string memory label,
        address wrapper
    ) internal pure returns (address) {
        return
            address(
                uint160(uint256(keccak256(abi.encodePacked(label, wrapper))))
            );
    }

    function _borrower(
        ChainlinkOEVWrapper wrapper
    ) internal pure returns (address) {
        return _perWrapperActor("BORROWER", address(wrapper));
    }

    function _liquidator(
        ChainlinkOEVWrapper wrapper
    ) internal pure returns (address) {
        return _perWrapperActor("LIQUIDATOR", address(wrapper));
    }

    function _mintMToken(
        address user,
        address mToken,
        uint256 amount
    ) internal {
        address underlying = MErc20(mToken).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(
                addresses.getAddress("WETH"),
                addresses.getAddress("WETH").balance + amount
            );
        }
        deal(underlying, user, amount);
        vm.startPrank(user);

        IERC20(underlying).approve(mToken, amount);

        assertEq(
            MErc20Delegator(payable(mToken)).mint(amount),
            0,
            "Mint failed"
        );
        vm.stopPrank();
    }

    function testReturnPreviousRoundIfNoOneHasPaidForCurrentRoundAndNewRoundIsWithinMaxRoundDelay()
        public
    {
        int256 mockPrice = 3_3333e8; // chainlink oracle uses 8 decimals
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];

            uint256 latestRoundOnChain = wrapper.priceFeed().latestRound();

            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint256(latestRoundOnChain + 1),
                    mockPrice,
                    0,
                    block.timestamp,
                    uint256(latestRoundOnChain + 1)
                )
            );

            uint256 mockTimestamp = block.timestamp - 1;
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().getRoundData.selector,
                    uint80(latestRoundOnChain)
                ),
                abi.encode(
                    uint80(latestRoundOnChain),
                    mockPrice,
                    0,
                    mockTimestamp,
                    uint80(latestRoundOnChain)
                )
            );

            (uint256 roundId, int256 answer, , uint256 timestamp, ) = wrapper
                .latestRoundData();

            assertEq(
                roundId,
                latestRoundOnChain,
                "Round ID should be the same"
            );
            assertEq(mockPrice, answer, "Price should be the same as answer");
            assertEq(
                timestamp,
                mockTimestamp,
                "Timestamp should be the same as block.timestamp"
            );
        }
    }

    function testReturnLatestRoundIfBlockTimestampIsOlderThanBlockTImestampPlusMaxRoundDelay()
        public
    {
        int256 mockPrice = 3_000e8; // chainlink oracle uses 8 decimals
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            uint256 latestRoundOnChain = wrapper.priceFeed().latestRound();
            uint256 expectedTimestamp = block.timestamp;

            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint256(latestRoundOnChain + 1),
                    mockPrice,
                    0,
                    block.timestamp,
                    uint256(latestRoundOnChain + 1)
                )
            );

            vm.warp(block.timestamp + wrapper.maxRoundDelay());

            (uint256 roundID, int256 answer, , uint256 timestamp, ) = wrapper
                .latestRoundData();

            assertEq(
                roundID,
                latestRoundOnChain + 1,
                "Round ID should be the same"
            );
            assertEq(mockPrice, answer, "Price should be the same as answer");
            assertEq(
                timestamp,
                expectedTimestamp,
                "Timestamp should be the same as block.timestamp"
            );
        }
    }

    function testSetLiquidatorFeeBps() public {
        uint16 newMultiplier = 100; // 1%
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            uint16 originalMultiplier = wrapper.liquidatorFeeBps();
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            vm.expectEmit(address(wrapper));
            emit LiquidatorFeeBpsChanged(originalMultiplier, newMultiplier);
            wrapper.setLiquidatorFeeBps(newMultiplier);
            assertEq(
                wrapper.liquidatorFeeBps(),
                newMultiplier,
                "Liquidator fee bps not updated"
            );
        }
    }

    function testSetLiquidatorFeeBpsRevertNonOwner() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            vm.expectRevert("Ownable: caller is not the owner");
            wrapper.setLiquidatorFeeBps(1);
        }
    }

    function testGetRoundData() public {
        uint80 roundId = 1;
        int256 mockPrice = 3_000e8;
        uint256 mockTimestamp = block.timestamp;
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            // Mock the original feed's getRoundData response
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().getRoundData.selector,
                    roundId
                ),
                abi.encode(
                    roundId,
                    mockPrice,
                    uint256(0),
                    mockTimestamp,
                    roundId
                )
            );

            (
                uint80 returnedRoundId,
                int256 answer,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = wrapper.getRoundData(roundId);

            assertEq(returnedRoundId, roundId, "Round ID should be the same");
            assertEq(answer, mockPrice, "Price should be the same");
            assertEq(startedAt, 0, "StartedAt should be 0");
            assertEq(
                updatedAt,
                mockTimestamp,
                "UpdatedAt should be the same as block.timestamp"
            );
            assertEq(
                answeredInRound,
                roundId,
                "AnsweredInRound should be the same as round ID"
            );
        }
    }

    function testAllChainlinkOraclesAreSet() public view {
        // Get all markets from the comptroller
        MToken[] memory allMarkets = comptroller.getAllMarkets();

        // Get the oracle from the comptroller
        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));

        for (uint i = 0; i < allMarkets.length; i++) {
            // Skip LBTC market if configured in addresses (external Redstone requirements on some forks)
            if (addresses.isAddressSet("MOONWELL_LBTC")) {
                if (
                    address(allMarkets[i]) ==
                    addresses.getAddress("MOONWELL_LBTC")
                ) {
                    continue;
                }
            }
            address underlying = MErc20(address(allMarkets[i])).underlying();

            // Get token symbol
            string memory symbol = IERC20(underlying).symbol();

            // Try to get price - this will revert if oracle is not set
            uint price = oracle.getUnderlyingPrice(MToken(allMarkets[i]));

            // Price should not be 0
            assertTrue(
                price > 0,
                string(abi.encodePacked("Oracle not set for ", symbol))
            );
        }
    }

    function testLatestRoundDataRevertOnChainlinkPriceIsZero() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            uint256 timestampBefore = vm.getBlockTimestamp();
            vm.warp(timestampBefore + uint256(wrapper.maxRoundDelay()));

            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(1), // roundId
                    int256(0), // answer
                    uint256(0), // startedAt
                    uint256(timestampBefore), // updatedAt
                    uint80(1) // answeredInRound
                )
            );

            vm.expectRevert("Chainlink price cannot be lower or equal to 0");
            wrapper.latestRoundData();
        }
    }

    function testLatestRoundDataRevertOnIncompleteRoundState() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRound.selector
                ),
                abi.encode(uint256(1))
            );

            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(1), // roundId
                    int256(3_000e8), // answer
                    uint256(0), // startedAt
                    uint256(0), // updatedAt - set to 0 to simulate incomplete state
                    uint80(1) // answeredInRound
                )
            );

            vm.expectRevert("Round is in incompleted state");
            wrapper.latestRoundData();
        }
    }

    function testLatestRoundDataRevertOnStalePriceData() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            uint256 timestampBefore = vm.getBlockTimestamp();
            vm.warp(timestampBefore + uint256(wrapper.maxRoundDelay()));

            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(2), // roundId
                    int256(3_000e8), // answer
                    uint256(0), // startedAt
                    timestampBefore, // updatedAt
                    uint80(1) // answeredInRound - less than roundId to simulate stale price
                )
            );

            vm.expectRevert("Stale price");
            wrapper.latestRoundData();
        }
    }

    function testNoUpdateEarlyReturnsPreviousRound() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRound.selector
                ),
                abi.encode(uint256(2))
            );
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(2), // roundId
                    int256(3_000e8), // answer
                    uint256(0), // startedAt
                    uint256(block.timestamp), // updatedAt
                    uint80(3) // answeredInRound
                )
            );
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().getRoundData.selector
                ),
                abi.encode(
                    uint80(1),
                    int256(3_001e8),
                    uint256(0),
                    uint256(block.timestamp - 1),
                    uint80(2)
                )
            );
            // Call latestRoundData on the wrapper
            (
                uint80 roundId,
                int256 price,
                uint256 startedAt,
                uint256 updatedAt,
                uint80 answeredInRound
            ) = wrapper.latestRoundData();

            // Assert that the round data matches the previous round data
            assertEq(roundId, 1, "Round ID should be the previous round");
            assertEq(price, 3_001e8, "Price should be the previous price");
            assertEq(
                startedAt,
                0,
                "Started at timestamp should be the previous timestamp"
            );
            assertEq(
                updatedAt,
                block.timestamp - 1,
                "Updated at timestamp should be the previous timestamp"
            );
            assertEq(
                answeredInRound,
                2,
                "Answered in round should be the previous round"
            );
        }
    }

    function testMaxDecrementsLimit() public {
        // Mock the feed to return valid data for specific rounds
        uint256 latestRound = 100;
        for (uint256 i = 0; i < wrappers.length; i++) {
            vm.clearMockedCalls();

            ChainlinkOEVWrapper wrapper = wrappers[i];

            // Mock valid price data for round 100 (latest)
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(latestRound),
                    int256(1000),
                    uint256(block.timestamp),
                    uint256(block.timestamp),
                    uint80(latestRound)
                )
            );

            // Should return latest price since we can't find valid price within configured decrements when none mocked
            (
                uint80 roundId,
                int256 answer,
                ,
                ,
                uint80 answeredInRound
            ) = wrapper.latestRoundData();
            assertEq(
                answer,
                1000,
                "Should return latest price when valid price not found within maxDecrements"
            );
            assertEq(
                roundId,
                uint80(latestRound),
                "Should return latest round ID"
            );
            assertEq(
                answeredInRound,
                uint80(latestRound),
                "Should return latest answered round"
            );

            // Mock valid price data for round 95
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().getRoundData.selector,
                    uint80(latestRound - 5)
                ),
                abi.encode(
                    uint80(latestRound - 5),
                    int256(950),
                    uint256(block.timestamp - 1 hours),
                    uint256(block.timestamp - 1 hours),
                    uint80(latestRound - 5)
                )
            );

            // Should return price from round 95
            (roundId, answer, , , answeredInRound) = wrapper.latestRoundData();
            assertEq(
                answer,
                950,
                "Should return price from round 95 when maxDecrements allows reaching it"
            );
            assertEq(
                roundId,
                uint80(latestRound - 5),
                "Should return round 95 ID"
            );
            assertEq(
                answeredInRound,
                uint80(latestRound - 5),
                "Should return round 95 as answered round"
            );
        }
    }

    /** updatePriceEarlyAndLiquidate */

    function testUpdatePriceEarlyAndLiquidate_Succeeds() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );

        for (uint256 i = 0; i < wrappers.length; i++) {
            vm.clearMockedCalls();

            ChainlinkOEVWrapper wrapper = wrappers[i];

            // Get the collateral mToken
            string memory mTokenKey = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKey)) continue;

            address mTokenCollateralAddr = addresses.getAddress(mTokenKey);

            // Get borrow token based on collateral type
            (
                string memory borrowMTokenKey,
                string memory borrowTokenSymbol
            ) = _getBorrowTokenForCollateral(oracleConfigs[i].symbol);

            address mTokenBorrowAddr = addresses.getAddress(borrowMTokenKey);

            // Set up synthetic position
            address borrower = _borrower(wrapper);
            address liquidator = _liquidator(wrapper);
            (, uint256 borrowAmount) = _setupSyntheticPosition(
                mTokenCollateralAddr,
                mTokenBorrowAddr,
                borrower
            );

            // Crash price to make position underwater
            _crashPriceForLiquidation(wrapper, borrower);

            // Create synthetic liquidation data
            LiquidationData memory liquidation = LiquidationData({
                timestamp: block.timestamp,
                blockNumber: block.number,
                borrowedToken: borrowTokenSymbol,
                collateralToken: IERC20(
                    addresses.getAddress(oracleConfigs[i].symbol)
                ).symbol(),
                borrowMTokenKey: borrowMTokenKey,
                collateralMTokenKey: oracleConfigs[i].mTokenKey,
                borrower: borrower,
                liquidator: liquidator,
                repayAmount: borrowAmount / 10,
                seizedCollateralAmount: 0, // Will be determined during liquidation
                liquidationSizeUSD: 0 // Not used in test
            });

            _testRealLiquidation(liquidation);
        }
    }

    /// @notice Get appropriate borrow token based on collateral type
    /// @dev Uses DAI for stablecoin collateral to avoid price correlation during liquidation tests
    /// @param collateralSymbol The symbol of the collateral asset
    /// @return borrowMTokenKey The key for the borrow mToken (e.g., "MOONWELL_DAI")
    /// @return borrowTokenSymbol The symbol of the borrow token (e.g., "DAI")
    function _getBorrowTokenForCollateral(
        string memory collateralSymbol
    )
        internal
        pure
        returns (string memory borrowMTokenKey, string memory borrowTokenSymbol)
    {
        if (
            keccak256(bytes(collateralSymbol)) == keccak256(bytes("USDC")) ||
            keccak256(bytes(collateralSymbol)) == keccak256(bytes("EURC"))
        ) {
            return ("MOONWELL_DAI", "DAI");
        } else {
            return ("MOONWELL_USDC", "USDC");
        }
    }

    /// @notice Set up synthetic position by depositing collateral and borrowing
    /// @return collateralAmount The amount of collateral deposited
    /// @return borrowAmount The amount borrowed
    function _setupSyntheticPosition(
        address mTokenCollateralAddr,
        address mTokenBorrowAddr,
        address borrower
    ) internal returns (uint256 collateralAmount, uint256 borrowAmount) {
        (collateralAmount, borrowAmount) = _calculateSyntheticAmounts(
            mTokenCollateralAddr,
            mTokenBorrowAddr
        );
        _depositCollateral(
            mTokenCollateralAddr,
            mTokenBorrowAddr,
            borrower,
            collateralAmount
        );
        _borrow(mTokenBorrowAddr, borrower, borrowAmount);
    }

    /// @notice Calculate collateral and borrow amounts for synthetic position
    function _calculateSyntheticAmounts(
        address mTokenCollateralAddr,
        address mTokenBorrowAddr
    ) internal view returns (uint256 collateralAmount, uint256 borrowAmount) {
        // Use oracle's getUnderlyingPrice which normalizes all prices to USD
        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));
        uint256 priceInUSD = oracle.getUnderlyingPrice(
            MToken(mTokenCollateralAddr)
        );
        require(priceInUSD > 0, "invalid price");

        (bool isListed, uint256 collateralFactorMantissa) = comptroller.markets(
            mTokenCollateralAddr
        );
        require(isListed, "market not listed");
        uint256 collateralFactorBps = (collateralFactorMantissa * 10000) / 1e18;

        uint256 borrowDecimals = IERC20(MErc20(mTokenBorrowAddr).underlying())
            .decimals();

        collateralAmount = (10_000 * 1e18 * 1e18) / priceInUSD;
        borrowAmount =
            ((10_000 * collateralFactorBps * 70) / (10000 * 100)) *
            (10 ** borrowDecimals);
    }

    /// @notice Deposit collateral and enter markets
    function _depositCollateral(
        address mTokenCollateralAddr,
        address mTokenBorrowAddr,
        address borrower,
        uint256 collateralAmount
    ) internal {
        MToken mToken = MToken(mTokenCollateralAddr);
        if (block.timestamp <= mToken.accrualBlockTimestamp()) {
            vm.warp(mToken.accrualBlockTimestamp() + 1);
        }

        _adjustSupplyCapIfNeeded(mTokenCollateralAddr, collateralAmount);
        _mintMToken(borrower, mTokenCollateralAddr, collateralAmount);

        address[] memory markets = new address[](2);
        markets[0] = mTokenCollateralAddr;
        markets[1] = mTokenBorrowAddr;
        vm.prank(borrower);
        comptroller.enterMarkets(markets);
    }

    /// @notice Adjust supply cap if needed
    function _adjustSupplyCapIfNeeded(
        address mTokenCollateralAddr,
        uint256 collateralAmount
    ) internal {
        uint256 supplyCap = comptroller.supplyCaps(mTokenCollateralAddr);
        if (supplyCap == 0) return;

        MToken mToken = MToken(mTokenCollateralAddr);
        uint256 totalSupply = mToken.totalSupply();
        uint256 exchangeRate = mToken.exchangeRateStored();
        uint256 totalUnderlyingSupply = (totalSupply * exchangeRate) / 1e18;

        if (totalUnderlyingSupply + collateralAmount >= supplyCap) {
            vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            MToken[] memory mTokens = new MToken[](1);
            mTokens[0] = mToken;
            uint256[] memory newCaps = new uint256[](1);
            newCaps[0] = (totalUnderlyingSupply + collateralAmount) * 2;
            comptroller._setMarketSupplyCaps(mTokens, newCaps);
            vm.stopPrank();
        }
    }

    /// @notice Borrow USDC or DAI
    function _borrow(
        address mTokenBorrowAddr,
        address borrower,
        uint256 borrowAmount
    ) internal {
        MToken mToken = MToken(mTokenBorrowAddr);
        if (block.timestamp <= mToken.accrualBlockTimestamp()) {
            vm.warp(mToken.accrualBlockTimestamp() + 1);
        }

        _adjustBorrowCapIfNeeded(mTokenBorrowAddr, borrowAmount);

        vm.prank(borrower);
        assertEq(
            MErc20Delegator(payable(mTokenBorrowAddr)).borrow(borrowAmount),
            0,
            "borrow failed"
        );
    }

    /// @notice Adjust borrow cap if needed
    function _adjustBorrowCapIfNeeded(
        address mTokenBorrowAddr,
        uint256 borrowAmount
    ) internal {
        uint256 cap = comptroller.borrowCaps(mTokenBorrowAddr);
        if (cap == 0) return;

        MToken mToken = MToken(mTokenBorrowAddr);
        uint256 total = mToken.totalBorrows();

        if (total + borrowAmount >= cap) {
            vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            MToken[] memory mTokens = new MToken[](1);
            mTokens[0] = mToken;
            uint256[] memory newCaps = new uint256[](1);
            newCaps[0] = (total + borrowAmount) * 2;
            comptroller._setMarketBorrowCaps(mTokens, newCaps);
            vm.stopPrank();
        }
    }

    /// @notice Crash price to make position underwater (for synthetic tests)
    function _crashPriceForLiquidation(
        ChainlinkOEVWrapper wrapper,
        address borrower
    ) internal {
        (, int256 price, , , ) = wrapper.latestRoundData();
        int256 crashedPrice = (price * 40) / 100; // 60% price drop

        uint80 roundId = 777;
        vm.mockCall(
            address(wrapper.priceFeed()),
            abi.encodeWithSelector(
                wrapper.priceFeed().latestRoundData.selector
            ),
            abi.encode(
                roundId,
                crashedPrice,
                uint256(0),
                block.timestamp,
                roundId
            )
        );

        // Verify position is now underwater
        (uint256 err, , uint256 shortfall) = comptroller.getAccountLiquidity(
            borrower
        );
        require(err == 0 && shortfall > 0, "position not underwater");
    }

    /// @notice Helper function to redeem protocol fees and verify the redemption
    /// @param mTokenCollateralAddr Address of the collateral mToken
    function _redeemAndVerifyProtocolFees(
        address mTokenCollateralAddr
    ) internal {
        uint256 reservesBeforeRedeem = MErc20(mTokenCollateralAddr)
            .totalReserves();
        redeemer.redeemAndAddReserves(mTokenCollateralAddr);
        uint256 reservesAfterRedeem = MErc20(mTokenCollateralAddr)
            .totalReserves();

        // Verify reserves increased after redemption
        assertGt(
            reservesAfterRedeem,
            reservesBeforeRedeem,
            "Reserves should increase after redeeming protocol fees"
        );

        // Verify redeemer no longer has mTokens
        assertEq(
            MErc20(mTokenCollateralAddr).balanceOf(address(redeemer)),
            0,
            "Redeemer should have no mTokens after redemption"
        );
    }

    function testUpdatePriceEarlyAndLiquidate_RevertZeroRepay() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                0,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertZeroBorrower() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0),
                1,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertZeroMToken() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                address(0),
                address(0xBEEF)
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertFeeZeroWhenMultiplierZero()
        public
    {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            wrapper.setLiquidatorFeeBps(0);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertInvalidPrice() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            // answer <= 0
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(1),
                    int256(0),
                    uint256(0),
                    block.timestamp,
                    uint80(1)
                )
            );
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertIncompleteRound() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            // updatedAt == 0
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(1),
                    int256(3_000e8),
                    uint256(0),
                    uint256(0),
                    uint80(1)
                )
            );
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertStalePrice() public {
        OracleConfig[] memory oracleConfigs = getOracleConfigurations(
            block.chainid
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVWrapper wrapper = wrappers[i];
            string memory mTokenKeyCandidate = string(
                abi.encodePacked("MOONWELL_", oracleConfigs[i].symbol)
            );
            if (!addresses.isAddressSet(mTokenKeyCandidate)) {
                continue;
            }
            // answeredInRound < roundId
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(2),
                    int256(3_000e8),
                    uint256(0),
                    block.timestamp,
                    uint80(1)
                )
            );
            address mTokenAddr = addresses.getAddress(mTokenKeyCandidate);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                mTokenAddr,
                mTokenAddr
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertLiquidationFailed() public {
        // Use ETH/WETH for this test
        ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
            payable(addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER"))
        );
        MToken mTokenCollateral = MToken(addresses.getAddress("MOONWELL_WETH"));
        MToken mTokenBorrow = MToken(addresses.getAddress("MOONWELL_USDC"));
        address borrower = _borrower(wrapper);
        uint256 borrowAmount;

        // 1) Deposit WETH as collateral
        {
            uint256 accrualTsPre = mTokenCollateral.accrualBlockTimestamp();
            if (block.timestamp <= accrualTsPre) {
                vm.warp(accrualTsPre + 1);
            }

            uint256 supplyAmount = 1 ether;
            _mintMToken(borrower, address(mTokenCollateral), supplyAmount);

            address[] memory markets = new address[](2);
            markets[0] = address(mTokenCollateral);
            markets[1] = address(mTokenBorrow);
            vm.prank(borrower);
            comptroller.enterMarkets(markets);

            assertTrue(
                comptroller.checkMembership(borrower, mTokenCollateral),
                "not in collateral market"
            );
        }

        // 2) Borrow USDC against WETH collateral (but stay healthy)
        {
            uint256 accrualTsPre = mTokenBorrow.accrualBlockTimestamp();
            if (block.timestamp <= accrualTsPre) {
                vm.warp(accrualTsPre + 1);
            }

            // Borrow only 1,000 USDC (well below 80% LTV, so position stays healthy)
            borrowAmount = 1_000 * 1e6;

            uint256 currentBorrowCap = comptroller.borrowCaps(
                address(mTokenBorrow)
            );
            uint256 totalBorrows = mTokenBorrow.totalBorrows();
            uint256 nextTotalBorrows = totalBorrows + borrowAmount;

            if (currentBorrowCap != 0 && nextTotalBorrows >= currentBorrowCap) {
                vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
                MToken[] memory mTokens = new MToken[](1);
                mTokens[0] = mTokenBorrow;
                uint256[] memory newBorrowCaps = new uint256[](1);
                newBorrowCaps[0] = nextTotalBorrows * 2;
                comptroller._setMarketBorrowCaps(mTokens, newBorrowCaps);
                vm.stopPrank();
            }

            vm.prank(borrower);
            assertEq(
                MErc20Delegator(payable(address(mTokenBorrow))).borrow(
                    borrowAmount
                ),
                0,
                "borrow failed"
            );
        }

        // 3) Verify position is healthy (has liquidity, no shortfall)
        {
            (uint256 err, uint256 liq, uint256 shortfall) = comptroller
                .getAccountLiquidity(borrower);
            assertEq(err, 0, "liquidity error");
            assertGt(liq, 0, "expected liquidity");
            assertEq(shortfall, 0, "should have no shortfall");
        }

        // 4) Try to liquidate a healthy position - should fail
        {
            address liquidator = _liquidator(wrapper);
            uint256 repayAmount = borrowAmount / 10; // Try to repay 100 USDC
            address borrowUnderlying = MErc20(address(mTokenBorrow))
                .underlying();
            deal(borrowUnderlying, liquidator, repayAmount);

            vm.startPrank(liquidator);
            IERC20(borrowUnderlying).approve(address(wrapper), repayAmount);

            if (block.timestamp <= mTokenBorrow.accrualBlockTimestamp()) {
                vm.warp(mTokenBorrow.accrualBlockTimestamp() + 1);
            }

            // Liquidation should fail because position is healthy (not underwater)
            vm.expectRevert(bytes("ChainlinkOEVWrapper: liquidation failed"));
            wrapper.updatePriceEarlyAndLiquidate(
                borrower,
                repayAmount,
                address(mTokenCollateral),
                address(mTokenBorrow)
            );
            vm.stopPrank();
        }
    }

    /// @notice Simulate some real liquidations from 10/10
    function testRealLiquidations() public {
        // NOTE: skipping real liquidations given protocol fee oev redeemer not deployed yet
        vm.skip(true);

        LiquidationData[] memory liquidations = getLiquidations();

        // Skip test if no liquidation data for this chain
        if (liquidations.length == 0) {
            return;
        }

        for (uint256 i = 0; i < liquidations.length; i++) {
            _testRealLiquidation(liquidations[i]);
        }
    }

    function _mockValidRound(
        ChainlinkOEVWrapper wrapper,
        uint80 roundId_,
        int256 price_
    ) internal {
        vm.mockCall(
            address(wrapper.priceFeed()),
            abi.encodeWithSelector(
                wrapper.priceFeed().latestRoundData.selector
            ),
            abi.encode(roundId_, price_, uint256(0), block.timestamp, roundId_)
        );
    }

    /// @notice Test liquidation using real liquidation data
    function _testRealLiquidation(LiquidationData memory liquidation) internal {
        (
            address mTokenCollateralAddr,
            address mTokenBorrowAddr,
            ChainlinkOEVWrapper wrapper
        ) = _setupLiquidation(liquidation);

        bool shouldContinue = _prepareLiquidation(
            liquidation,
            mTokenCollateralAddr,
            mTokenBorrowAddr,
            wrapper
        );
        if (!shouldContinue) {
            console2.log("Position doesn't exist, skipping");
            return;
        }

        LiquidationState memory state = _executeLiquidation(
            liquidation,
            wrapper,
            mTokenCollateralAddr,
            mTokenBorrowAddr
        );

        _assertLiquidationResults(state);

        // _verifyLiquidationResults(
        //     liquidation,
        //     state,
        //     mTokenCollateralAddr,
        //     mTokenBorrowAddr
        // );
    }

    /// @notice Setup liquidation by getting addresses and finding wrapper
    function _setupLiquidation(
        LiquidationData memory liquidation
    )
        internal
        view
        returns (
            address mTokenCollateralAddr,
            address mTokenBorrowAddr,
            ChainlinkOEVWrapper wrapper
        )
    {
        require(
            addresses.isAddressSet(liquidation.collateralMTokenKey),
            "Collateral mToken not found"
        );
        require(
            addresses.isAddressSet(liquidation.borrowMTokenKey),
            "Borrow mToken not found"
        );

        mTokenCollateralAddr = addresses.getAddress(
            liquidation.collateralMTokenKey
        );
        mTokenBorrowAddr = addresses.getAddress(liquidation.borrowMTokenKey);

        bool found;
        (wrapper, found) = _findWrapperForCollateral(
            liquidation.collateralToken
        );
        require(found, "Wrapper not found for collateral token");
    }

    /// @notice Prepare liquidation by warping time and validating position
    /// @return shouldContinue True if liquidation should proceed, false if position doesn't exist
    function _prepareLiquidation(
        LiquidationData memory liquidation,
        address mTokenCollateralAddr,
        address mTokenBorrowAddr,
        ChainlinkOEVWrapper wrapper
    ) internal returns (bool shouldContinue) {
        // Skip fork rolling for synthetic tests (blockNumber == current block.number)
        // Real liquidations have historical block numbers
        if (liquidation.blockNumber != block.number) {
            vm.rollFork(liquidation.blockNumber - 1); // ensure onchain state
            vm.warp(liquidation.timestamp - 1); // ensures mToken accrual timestamps
        }

        address borrower = liquidation.borrower;
        MToken mTokenBorrow = MToken(mTokenBorrowAddr);
        MToken mTokenCollateral = MToken(mTokenCollateralAddr);

        // NOTE: this seems to be needed to get past some "delta" errors
        // Explicitly accrue interest at the current timestamp to ensure accrual timestamps are set correctly
        mTokenBorrow.accrueInterest();
        mTokenCollateral.accrueInterest();

        uint256 borrowBalance = mTokenBorrow.borrowBalanceStored(borrower);
        if (borrowBalance == 0) {
            return false; // Position doesn't exist, skip
        }

        // Skip price mocking for synthetic tests (price already crashed in _crashPriceForLiquidation)
        // Only mock price for real liquidations
        if (liquidation.blockNumber != block.number) {
            // Mock collateral price down to make position underwater
            AggregatorV3Interface priceFeed = wrapper.priceFeed();
            (uint80 feedRoundId, int256 price, , , ) = priceFeed
                .latestRoundData();
            int256 crashedPrice = (price * 75) / 100; // 25% price drop
            uint80 latestRoundId = feedRoundId;
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    latestRoundId,
                    crashedPrice,
                    uint256(0),
                    block.timestamp,
                    latestRoundId
                )
            );

            // Mock getRoundData for previous rounds
            _mockPreviousRounds(
                wrapper,
                latestRoundId,
                crashedPrice,
                block.timestamp
            );
        }

        // Verify position is now underwater after price crash
        (uint256 err, , uint256 shortfall) = comptroller.getAccountLiquidity(
            borrower
        );
        require(err == 0 && shortfall > 0, "Position not underwater");
        return true;
    }

    /// @notice Mock previous rounds for price feed to handle wrapper's round search logic
    function _mockPreviousRounds(
        ChainlinkOEVWrapper wrapper,
        uint80 latestRoundId,
        int256 crashedPrice,
        uint256 timestamp
    ) internal {
        uint256 maxDecrements = wrapper.maxDecrements();
        AggregatorV3Interface priceFeed = wrapper.priceFeed();

        uint80 startRound = latestRoundId > maxDecrements
            ? uint80(latestRoundId - maxDecrements)
            : 1;

        for (uint80 i = startRound; i < latestRoundId; i++) {
            uint256 roundTimestamp = timestamp -
                uint256(latestRoundId - i) *
                12;
            vm.mockCall(
                address(priceFeed),
                abi.encodeWithSelector(priceFeed.getRoundData.selector, i),
                abi.encode(i, crashedPrice, uint256(0), roundTimestamp, i)
            );
        }
    }

    /// @notice Execute the liquidation
    function _executeLiquidation(
        LiquidationData memory liquidation,
        ChainlinkOEVWrapper wrapper,
        address mTokenCollateralAddr,
        address mTokenBorrowAddr
    ) internal returns (LiquidationState memory state) {
        address borrower = liquidation.borrower;
        address liquidator = liquidation.liquidator;
        uint256 repayAmount = liquidation.repayAmount;

        address borrowUnderlying = MErc20(mTokenBorrowAddr).underlying();
        deal(borrowUnderlying, liquidator, repayAmount * 2);
        vm.warp(liquidation.timestamp);

        // WIP; mocking onchain state for historical liquidations
        // // For historical liquidations, set up the necessary state
        // // At block N-1, they may not have had the position yet or been underwater
        // if (liquidation.blockNumber != block.number) {
        //     // Give borrower enough collateral (accountTokens is at slot 14)
        //     bytes32 collateralSlot = keccak256(abi.encode(borrower, uint256(14)));
        //     vm.store(mTokenCollateralAddr, collateralSlot, bytes32(uint256(1e25))); // 10M mTokens

        //     // Mock liquidateBorrowAllowed to always return success
        //     vm.mockCall(
        //         address(comptroller),
        //         abi.encodeWithSignature(
        //             "liquidateBorrowAllowed(address,address,address,address,uint256)"
        //         ),
        //         abi.encode(uint256(0)) // Return 0 = success
        //     );
        // }

        MToken mTokenBorrow = MToken(mTokenBorrowAddr);
        MToken mTokenCollateral = MToken(mTokenCollateralAddr);

        // Get balances before liquidation
        state.borrowerBorrowBefore = mTokenBorrow.borrowBalanceStored(borrower);
        state.borrowerCollateralBefore = mTokenCollateral.balanceOf(borrower);
        state.reservesBefore = mTokenCollateral.totalReserves();

        uint256 liquidatorMTokenBefore = mTokenCollateral.balanceOf(liquidator);
        uint256 redeemerMTokenBefore = mTokenCollateral.balanceOf(
            address(redeemer)
        );

        // Execute liquidation
        vm.startPrank(liquidator);
        IERC20(borrowUnderlying).approve(address(wrapper), repayAmount);

        vm.recordLogs();
        wrapper.updatePriceEarlyAndLiquidate(
            borrower,
            repayAmount,
            mTokenCollateralAddr,
            mTokenBorrowAddr
        );
        vm.stopPrank();

        (
            state.protocolFee,
            state.liquidatorFeeReceived
        ) = _parseLiquidationEvent();

        // Verify liquidator received mTokens
        uint256 liquidatorMTokenAfter = mTokenCollateral.balanceOf(liquidator);
        assertGt(
            liquidatorMTokenAfter,
            liquidatorMTokenBefore,
            "Liquidator should receive mTokens"
        );
        assertEq(
            liquidatorMTokenAfter - liquidatorMTokenBefore,
            state.liquidatorFeeReceived,
            "Liquidator mToken balance should match liquidator fee from event"
        );

        // Verify redeemer received mTokens (protocol fee) - only if protocolFee > 0
        uint256 redeemerMTokenAfter = mTokenCollateral.balanceOf(
            address(redeemer)
        );
        if (state.protocolFee > 0) {
            assertGt(
                redeemerMTokenAfter,
                redeemerMTokenBefore,
                "Redeemer should receive protocol fee mTokens"
            );
            assertEq(
                redeemerMTokenAfter - redeemerMTokenBefore,
                state.protocolFee,
                "Redeemer mToken balance should match protocol fee from event"
            );

            // Get reserves before redemption
            uint256 reservesBeforeRedemption = mTokenCollateral.totalReserves();

            // Redeem protocol fees and add to reserves
            _redeemAndVerifyProtocolFees(mTokenCollateralAddr);

            // Get reserves after redemption
            uint256 reservesAfterRedemption = mTokenCollateral.totalReserves();

            // Calculate how much underlying was added to reserves
            state.protocolFeeRedeemed =
                reservesAfterRedemption -
                reservesBeforeRedemption;
        } else {
            // When protocolFee is 0, redeemer should not receive any mTokens
            assertEq(
                redeemerMTokenAfter,
                redeemerMTokenBefore,
                "Redeemer should not receive mTokens when protocolFee is 0"
            );
            state.protocolFeeRedeemed = 0;
        }

        // Get balances after liquidation and redemption
        state.borrowerBorrowAfter = mTokenBorrow.borrowBalanceStored(borrower);
        state.borrowerCollateralAfter = mTokenCollateral.balanceOf(borrower);
        state.reservesAfter = mTokenCollateral.totalReserves();
    }

    /// @notice Parse liquidation event to extract fees
    function _parseLiquidationEvent()
        internal
        returns (uint256 protocolFee, uint256 liquidatorFee)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256(
            "PriceUpdatedEarlyAndLiquidated(address,uint256,address,address,uint256,uint256)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                (, , , uint256 _protocolFee, uint256 _liquidatorFee) = abi
                    .decode(
                        logs[i].data,
                        (uint256, address, address, uint256, uint256)
                    );

                protocolFee = _protocolFee;
                liquidatorFee = _liquidatorFee;
            }
        }
    }

    /// @notice Struct to hold price and decimal info
    struct PriceInfo {
        uint256 collateralPriceUSD;
        uint256 borrowPriceUSD;
        uint8 collateralDecimals;
        uint8 borrowDecimals;
    }

    /// @notice Verify liquidation results and log
    /// @dev only needed to verify USD values on real liquidations
    function _verifyLiquidationResults(
        LiquidationData memory liquidation,
        LiquidationState memory state,
        address mTokenCollateralAddr,
        address mTokenBorrowAddr
    ) internal view {
        PriceInfo memory priceInfo = _getPriceInfo(
            mTokenCollateralAddr,
            mTokenBorrowAddr
        );
        USDValues memory usdValues = _calculateUSDValues(
            liquidation,
            state,
            priceInfo,
            mTokenCollateralAddr
        );

        _logLiquidationResults(
            liquidation,
            state,
            usdValues,
            mTokenCollateralAddr
        );
        _assertLiquidationResults(state);
    }

    /// @notice Get price and decimal information
    function _getPriceInfo(
        address mTokenCollateralAddr,
        address mTokenBorrowAddr
    ) internal view returns (PriceInfo memory) {
        ChainlinkOracle chainlinkOracle = ChainlinkOracle(
            address(comptroller.oracle())
        );

        uint256 collateralPriceUSD = chainlinkOracle.getUnderlyingPrice(
            MToken(mTokenCollateralAddr)
        );
        uint256 borrowPriceUSD = chainlinkOracle.getUnderlyingPrice(
            MToken(mTokenBorrowAddr)
        );

        address collateralUnderlying = MErc20(mTokenCollateralAddr)
            .underlying();
        address borrowUnderlying = MErc20(mTokenBorrowAddr).underlying();
        uint8 collateralDecimals = IERC20(collateralUnderlying).decimals();
        uint8 borrowDecimals = IERC20(borrowUnderlying).decimals();

        return
            PriceInfo({
                collateralPriceUSD: collateralPriceUSD,
                borrowPriceUSD: borrowPriceUSD,
                collateralDecimals: collateralDecimals,
                borrowDecimals: borrowDecimals
            });
    }

    /// @notice Struct to hold USD values
    struct USDValues {
        uint256 protocolFeeUSD;
        uint256 liquidatorFeeUSD;
        uint256 repayAmountUSD;
        uint256 protocolFeeUnderlying;
        uint256 liquidatorFeeUnderlying;
        uint256 protocolFeeRedeemedUSD;
    }

    /// @notice Calculate USD values from token amounts
    /// @dev Protocol and liquidator fees are in mToken units, need to convert to underlying using exchange rate
    /// @dev getUnderlyingPrice returns prices scaled by 1e18 and already adjusted for token decimals
    /// So: USD = (underlyingAmount * price) / 1e18
    function _calculateUSDValues(
        LiquidationData memory liquidation,
        LiquidationState memory state,
        PriceInfo memory priceInfo,
        address mTokenCollateralAddr
    ) internal view returns (USDValues memory) {
        uint256 repayAmount = liquidation.repayAmount;

        // Get exchange rate to convert mToken amounts to underlying amounts
        uint256 exchangeRate = MToken(mTokenCollateralAddr)
            .exchangeRateStored();

        // Convert mToken amounts to underlying amounts
        // exchangeRate has 18 decimals, so: underlying = (mTokenAmount * exchangeRate) / 1e18
        uint256 protocolFeeUnderlying = (state.protocolFee * exchangeRate) /
            1e18;
        uint256 liquidatorFeeUnderlying = (state.liquidatorFeeReceived *
            exchangeRate) / 1e18;

        // Calculate USD values from underlying amounts
        uint256 protocolFeeUSD = (protocolFeeUnderlying *
            priceInfo.collateralPriceUSD) / 1e18;
        uint256 liquidatorFeeUSD = (liquidatorFeeUnderlying *
            priceInfo.collateralPriceUSD) / 1e18;
        uint256 repayAmountUSD = (repayAmount * priceInfo.borrowPriceUSD) /
            1e18;

        // Calculate USD value of redeemed protocol fee (already in underlying units)
        uint256 protocolFeeRedeemedUSD = (state.protocolFeeRedeemed *
            priceInfo.collateralPriceUSD) / 1e18;

        return
            USDValues({
                protocolFeeUSD: protocolFeeUSD,
                liquidatorFeeUSD: liquidatorFeeUSD,
                repayAmountUSD: repayAmountUSD,
                protocolFeeUnderlying: protocolFeeUnderlying,
                liquidatorFeeUnderlying: liquidatorFeeUnderlying,
                protocolFeeRedeemedUSD: protocolFeeRedeemedUSD
            });
    }

    /// @notice Log liquidation results
    function _logLiquidationResults(
        LiquidationData memory liquidation,
        LiquidationState memory state,
        USDValues memory usdValues,
        address mTokenCollateralAddr
    ) internal view {
        console2.log("\n=== Liquidation Results ===\n");
        console2.log("Borrower:", liquidation.borrower);
        console2.log("Liquidator:", liquidation.liquidator);
        console2.log("Collateral Token:", liquidation.collateralToken);
        console2.log("Borrow Token:", liquidation.borrowedToken);
        console2.log("\n--- Repayment ---");
        console2.log("Repay Amount:", liquidation.repayAmount);
        console2.log("Repay Amount USD:", usdValues.repayAmountUSD);
        console2.log("\n--- Protocol Fee (OEV capture) ---");
        console2.log("Protocol Fee (mTokens):", state.protocolFee);
        console2.log(
            "Protocol Fee (underlying):",
            usdValues.protocolFeeUnderlying
        );
        console2.log("Protocol Fee USD:", usdValues.protocolFeeUSD);
        if (state.protocolFee > 0) {
            console2.log(
                "Protocol Fee Redeemed (underlying added to reserves):",
                state.protocolFeeRedeemed
            );
            console2.log(
                "Protocol Fee Redeemed USD:",
                usdValues.protocolFeeRedeemedUSD
            );
        }
        console2.log("\n--- Liquidator Fee ---");
        console2.log("Liquidator Fee (mTokens):", state.liquidatorFeeReceived);
        console2.log(
            "Liquidator Fee (underlying):",
            usdValues.liquidatorFeeUnderlying
        );
        console2.log("Liquidator Fee USD:", usdValues.liquidatorFeeUSD);
        console2.log("\n--- Collateral Seized (mTokens) ---");
        uint256 totalSeized = state.borrowerCollateralBefore -
            state.borrowerCollateralAfter;
        uint256 burnedMTokens = totalSeized -
            state.liquidatorFeeReceived -
            state.protocolFee;
        console2.log("Total Seized from Borrower:", totalSeized);
        console2.log("Distributed to Liquidator:", state.liquidatorFeeReceived);
        console2.log(
            "Distributed to Protocol (OEV Redeemer):",
            state.protocolFee
        );
        console2.log("Burned (protocol seize share):", burnedMTokens);

        // Calculate expected underlying from burned mTokens
        uint256 exchangeRate = MToken(mTokenCollateralAddr)
            .exchangeRateStored();
        uint256 burnedUnderlyingExpected = (burnedMTokens * exchangeRate) /
            1e18;
        console2.log(
            "Burned mTokens -> underlying (expected):",
            burnedUnderlyingExpected
        );

        console2.log("\n--- Borrower Position ---");
        console2.log("Borrower Borrow Before:", state.borrowerBorrowBefore);
        console2.log("Borrower Borrow After:", state.borrowerBorrowAfter);
        console2.log(
            "Borrower Collateral Before (mTokens):",
            state.borrowerCollateralBefore
        );
        console2.log(
            "Borrower Collateral After (mTokens):",
            state.borrowerCollateralAfter
        );
        console2.log("\n--- Reserves (underlying tokens) ---");
        console2.log("Reserves Before:", state.reservesBefore);
        console2.log("Reserves After:", state.reservesAfter);
        console2.log(
            "Reserves Increase:",
            state.reservesAfter - state.reservesBefore
        );
        if (state.protocolFee > 0) {
            uint256 reservesFromBurn = (state.reservesAfter -
                state.reservesBefore) - state.protocolFeeRedeemed;
            console2.log(
                "  - From protocol seize share (burned mTokens):",
                reservesFromBurn
            );
            console2.log(
                "  - From OEV capture (redeemed mTokens):",
                state.protocolFeeRedeemed
            );
        } else {
            console2.log("  - All from protocol seize share (burned mTokens)");
        }
        console2.log("\n--- Exchange Rate ---");
        console2.log("Exchange Rate:", exchangeRate);
        console2.log("\n==============================================\n");
    }

    /// @notice Assert liquidation results
    function _assertLiquidationResults(
        LiquidationState memory state
    ) internal pure {
        assertLt(
            state.borrowerBorrowAfter,
            state.borrowerBorrowBefore,
            "Borrow not reduced"
        );
        assertLt(
            state.borrowerCollateralAfter,
            state.borrowerCollateralBefore,
            "Collateral not seized"
        );
        assertGt(
            state.liquidatorFeeReceived,
            0,
            "Liquidator fee should be > 0"
        );
        // Protocol fee can be 0 when collateral value <= repayment value
        // Reserves only increase if protocolFee > 0 (after redemption)
        if (state.protocolFee > 0) {
            assertGt(
                state.reservesAfter,
                state.reservesBefore,
                "Reserves should increase when protocolFee > 0"
            );
        }
    }

    /// @notice Find the wrapper for a given collateral token symbol
    function _findWrapperForCollateral(
        string memory collateralSymbol
    ) internal view returns (ChainlinkOEVWrapper wrapper, bool found) {
        ChainlinkOracle chainlinkOracle = ChainlinkOracle(
            address(comptroller.oracle())
        );
        for (uint256 i = 0; i < wrappers.length; i++) {
            try chainlinkOracle.getFeed(collateralSymbol) returns (
                AggregatorV3Interface feed
            ) {
                if (address(feed) == address(wrappers[i])) {
                    return (wrappers[i], true);
                }
            } catch {
                continue;
            }
        }
        return (ChainlinkOEVWrapper(payable(address(0))), false);
    }
}

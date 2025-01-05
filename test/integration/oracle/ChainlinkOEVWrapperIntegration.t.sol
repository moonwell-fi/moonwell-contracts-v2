pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract ChainlinkOEVWrapperIntegrationTest is PostProposalCheck {
    event FeeMultiplierChanged(uint8 oldFee, uint8 newFee);
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded,
        uint256 roundId
    );
    event MaxDecrementsChanged(uint8 oldMaxDecrements, uint8 newMaxDecrements);
    event NewMaxRoundDelay(uint8 oldWindow, uint8 newWindow);

    ChainlinkFeedOEVWrapper public wrapper;
    Comptroller comptroller;
    MarketBase public marketBase;

    uint256 public constant multiplier = 99;
    uint256 latestRoundOnChain;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");

        super.setUp();
        vm.selectFork(primaryForkId);
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);

        // Deploy a new wrapper for testing
        wrapper = ChainlinkFeedOEVWrapper(
            addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER")
        );

        // get latest round
        latestRoundOnChain = wrapper.originalFeed().latestRound();
    }

    function _mintMToken(
        address user,
        address mToken,
        uint256 amount
    ) internal {
        address underlying = MErc20(mToken).underlying();

        if (underlying == addresses.getAddress("WETH")) {
            vm.deal(addresses.getAddress("WETH"), amount);
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

    function testCanUpdatePriceEarly() public {
        vm.warp(vm.getBlockTimestamp() + 1 days);

        int256 mockPrice = 3_000e8; // chainlink oracle uses 8 decimals

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei
        vm.expectEmit(address(wrapper));
        emit ProtocolOEVRevenueUpdated(
            addresses.getAddress("MOONWELL_WETH"),
            tax,
            uint256(latestRoundOnChain + 1)
        );

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint256(latestRoundOnChain + 1),
                mockPrice,
                0,
                block.timestamp,
                uint256(latestRoundOnChain + 1)
            )
        );

        wrapper.updatePriceEarly{value: tax}();

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector,
                uint80(latestRoundOnChain + 1)
            ),
            abi.encode(
                uint80(latestRoundOnChain + 1),
                mockPrice,
                0,
                block.timestamp,
                uint80(latestRoundOnChain + 1)
            )
        );

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(latestRoundOnChain + 1))
        );

        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(
            timestamp,
            block.timestamp - 1,
            "Timestamp should be the same as block.timestamp - 1"
        );

        // assert round id and timestamp are cached
        assertEq(
            wrapper.cachedRoundId(),
            latestRoundOnChain + 1,
            "Round id should be cached"
        );
        assertEq(
            wrapper.cachedTimestamp(),
            block.timestamp,
            "Timestamp should be cached"
        );
    }

    function testReturnPreviousRoundIfNoOneHasPaidForCurrentRound() public {
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(latestRoundOnChain + 1))
        );

        int256 mockPrice = 3_3333e8; // chainlink oracle uses 8 decimals
        uint256 mockTimestamp = block.timestamp - 1;
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector,
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

        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(
            timestamp,
            mockTimestamp,
            "Timestamp should be the same as block.timestamp"
        );
    }

    function testReturnPreviousRoundIfCachedTimestmapPlusEarlyUpdateWindowIsEqualToCurrentTimestamp()
        public
    {
        // current round after testCanUpdatePriceEarly is latestRoundOnChain + 1, get data for latestRoundOnChain
        (
            uint256 expectedRoundId,
            int256 expectedAnswer,
            ,
            uint256 expectedTimestamp,

        ) = wrapper.getRoundData(uint80(latestRoundOnChain));

        testCanUpdatePriceEarly();

        uint256 cachedRoundId = wrapper.cachedRoundId();
        uint256 cachedTimestamp = wrapper.cachedTimestamp();

        assertEq(
            cachedRoundId,
            latestRoundOnChain + 1,
            "Round id should be the same"
        );
        assertEq(
            cachedTimestamp,
            vm.getBlockTimestamp(),
            "Timestamp should be the same as block.timestamp"
        );

        vm.warp(vm.getBlockTimestamp() + wrapper.earlyUpdateWindow());
        (uint256 roundId, int256 answer, , uint256 timestamp, ) = wrapper
            .latestRoundData();

        assertEq(
            roundId,
            expectedRoundId,
            "Round id should be the same as expectedRoundId"
        );
        assertEq(
            answer,
            expectedAnswer,
            "Answer should be the same as expectedAnswer"
        );
        assertEq(
            timestamp,
            expectedTimestamp,
            "Timestamp should be the same as expectedTimestamp"
        );
    }

    function testRevertIfInsufficientTax() public {
        uint256 tax = 25 gwei * multiplier;
        vm.deal(address(this), tax - 1);

        vm.txGasPrice(50 gwei);
        vm.fee(25 gwei);
        vm.expectRevert("ChainlinkOEVWrapper: Insufficient tax");
        wrapper.updatePriceEarly{value: tax - 1}();
    }

    function testUpdatePriceEarlyOnLiquidationOpportunity() public {
        address user = address(0x1234);
        // Supply weth
        MToken mToken = MToken(addresses.getAddress("MOONWELL_WETH"));
        MToken mTokenBorrowed = MToken(addresses.getAddress("MOONWELL_USDC"));

        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);
        _mintMToken(user, address(mToken), mintAmount);
        {
            // Enter WETH and USDC markets
            vm.startPrank(user);
            address[] memory markets = new address[](2);
            markets[0] = address(mToken);
            markets[1] = address(mTokenBorrowed);
            comptroller.enterMarkets(markets);
            vm.stopPrank();
        }

        uint256 borrowAmount;
        {
            // Calculate maximum borrow amount
            (, uint256 liquidity, ) = comptroller.getAccountLiquidity(user);

            // Use 80% of max liquidity to leave room for price movement
            // usdc is 6 decimals, liquidity is in 18 decimals
            // so we need to convert borrow amount to 6 decimals
            borrowAmount = ((liquidity * 80) / 100) / 1e12; // Changed from full amount

            // before borrowing, increase borrow cap to make sure we borrow a significant amount
            vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
            MToken[] memory mTokens = new MToken[](1);
            mTokens[0] = mTokenBorrowed;
            uint256[] memory newBorrowCaps = new uint256[](1);
            uint256 currentBorrowCap = comptroller.borrowCaps(
                address(mTokens[0])
            );

            newBorrowCaps[0] = currentBorrowCap + borrowAmount;
            comptroller._setMarketBorrowCaps(mTokens, newBorrowCaps);
            vm.stopPrank();

            // make sure the mToken has enough underlying to borrow
            deal(
                MErc20(address(mTokenBorrowed)).underlying(),
                address(mTokenBorrowed),
                borrowAmount
            );

            vm.warp(block.timestamp + 1 days);
            vm.prank(user);
            uint256 err = MErc20(address(mTokenBorrowed)).borrow(borrowAmount);
            assertEq(err, 0, "Borrow failed");
        }

        {
            (, int256 priceBefore, , , ) = wrapper.latestRoundData();
            int256 newPrice = (priceBefore * 70) / 100; // 30% drop

            uint256 tax = (50 gwei - 25 gwei) *
                uint256(wrapper.feeMultiplier());
            vm.deal(address(this), tax);
            vm.txGasPrice(50 gwei);
            vm.fee(25 gwei);

            vm.mockCall(
                address(wrapper.originalFeed()),
                abi.encodeWithSelector(
                    wrapper.originalFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint256(latestRoundOnChain + 1),
                    newPrice,
                    0,
                    block.timestamp,
                    uint256(latestRoundOnChain + 1)
                )
            );
            wrapper.updatePriceEarly{value: tax}();
            vm.mockCall(
                address(wrapper.originalFeed()),
                abi.encodeWithSelector(
                    wrapper.originalFeed().getRoundData.selector,
                    uint80(latestRoundOnChain + 1)
                ),
                abi.encode(
                    uint80(latestRoundOnChain + 1),
                    newPrice,
                    0,
                    block.timestamp,
                    uint80(latestRoundOnChain + 1)
                )
            );

            vm.mockCall(
                address(wrapper.originalFeed()),
                abi.encodeWithSelector(
                    wrapper.originalFeed().latestRound.selector
                ),
                abi.encode(uint256(latestRoundOnChain + 1))
            );

            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
                .getHypotheticalAccountLiquidity(user, address(mToken), 0, 0);

            assertEq(err, 0, "Error in hypothetical liquidity calculation");
            assertEq(liquidity, 0, "Liquidity should be 0");
            assertGt(shortfall, 0, "Position should be underwater");
        }

        // Setup liquidator
        address liquidator = address(0x5678);
        uint256 repayAmount = borrowAmount / 4;

        deal(
            MErc20(address(mTokenBorrowed)).underlying(),
            liquidator,
            repayAmount
        );

        // Execute liquidation
        vm.startPrank(liquidator);
        IERC20(MErc20(address(mTokenBorrowed)).underlying()).approve(
            address(mTokenBorrowed),
            repayAmount
        );
        assertEq(
            MErc20Delegator(payable(address(mTokenBorrowed))).liquidateBorrow(
                user,
                repayAmount,
                MErc20(address(mToken))
            ),
            0,
            "Liquidation failed"
        );
        vm.stopPrank();
    }

    function testSetFeeMultiplier() public {
        uint8 newMultiplier = 1;

        uint8 originalMultiplier = wrapper.feeMultiplier();
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit FeeMultiplierChanged(originalMultiplier, newMultiplier);
        wrapper.setFeeMultiplier(newMultiplier);

        assertEq(
            wrapper.feeMultiplier(),
            newMultiplier,
            "Fee multiplier not updated"
        );
    }

    function testSetFeeMultiplierRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setFeeMultiplier(1);
    }

    function testmaxRoundDelay() public {
        uint8 newWindow = 3;

        uint8 originalWindow = wrapper.earlyUpdateWindow();
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit NewMaxRoundDelay(originalWindow, newWindow);
        wrapper.maxRoundDelay(newWindow);

        assertEq(
            wrapper.earlyUpdateWindow(),
            newWindow,
            "Early update window not updated"
        );
    }

    function testmaxRoundDelayRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.maxRoundDelay(10);
    }

    function testGetRoundData() public {
        uint80 roundId = 1;
        int256 mockPrice = 3_000e8;
        uint256 mockTimestamp = block.timestamp;

        // Mock the original feed's getRoundData response
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector,
                roundId
            ),
            abi.encode(roundId, mockPrice, uint256(0), mockTimestamp, roundId)
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

    function testFeeAmountIsAdddedToEthReserves() public {
        // accrue interest
        MErc20(addresses.getAddress("MOONWELL_WETH")).accrueInterest();
        uint256 wethBalanceBefore = IERC20(addresses.getAddress("WETH"))
            .balanceOf(addresses.getAddress("MOONWELL_WETH"));
        uint256 totalReservesBefore = MErc20(
            addresses.getAddress("MOONWELL_WETH")
        ).totalReserves();

        uint256 tax = 25 gwei * multiplier;
        vm.deal(address(this), tax);

        vm.txGasPrice(50 gwei);
        vm.fee(25 gwei);

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                latestRoundOnChain + 1,
                3_000e8,
                0,
                block.timestamp,
                latestRoundOnChain + 1
            )
        );
        wrapper.updatePriceEarly{value: tax}();

        uint256 totalReservesAfter = MErc20(
            addresses.getAddress("MOONWELL_WETH")
        ).totalReserves();

        assertEq(
            totalReservesBefore + tax,
            totalReservesAfter,
            "Total reserves should be increased by tax"
        );
        assertEq(
            wethBalanceBefore + tax,
            IERC20(addresses.getAddress("WETH")).balanceOf(
                addresses.getAddress("MOONWELL_WETH")
            ),
            "WETH balance should be increased by tax"
        );
    }

    function testAllChainlinkOraclesAreSet() public view {
        // Get all markets from the comptroller
        MToken[] memory allMarkets = comptroller.getAllMarkets();

        // Get the oracle from the comptroller
        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));

        for (uint i = 0; i < allMarkets.length; i++) {
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

    function testMultipleAccountHealthChecks() public {
        MToken[] memory allMarkets = comptroller.getAllMarkets();

        // Test 10 different accounts
        for (uint accountId = 0; accountId < 10; accountId++) {
            address account = address(uint160(0x1000 + accountId));

            // first enter all markets
            address[] memory markets = new address[](allMarkets.length);
            for (uint i = 0; i < allMarkets.length; i++) {
                markets[i] = address(allMarkets[i]);
            }
            vm.prank(account);
            comptroller.enterMarkets(markets);

            // Supply different amounts of each asset
            for (uint marketId = 0; marketId < allMarkets.length; marketId++) {
                MToken mToken = allMarkets[marketId];
                address underlying = MErc20(address(mToken)).underlying();

                // check max mint allowed
                uint256 maxMint = marketBase.getMaxSupplyAmount(mToken);

                if (maxMint == 0) {
                    continue;
                }

                // Mint different amounts based on account and market
                uint256 amount = 1000 *
                    (accountId + 1) *
                    (marketId + 1) *
                    (10 ** IERC20(underlying).decimals());

                if (amount > maxMint) {
                    amount = maxMint;
                }

                _mintMToken(account, address(mToken), amount);
            }

            // Check account liquidity
            (uint err, uint liquidity, uint shortfall) = comptroller
                .getAccountLiquidity(account);
            assertEq(err, 0, "Error getting account liquidity");
            assertGt(liquidity, 0, "Account should have positive liquidity");
            assertEq(shortfall, 0, "Account should have no shortfall");

            // Test hypothetical liquidity for each asset
            for (uint marketId = 0; marketId < allMarkets.length; marketId++) {
                MToken mToken = allMarkets[marketId];

                uint256 mTokenBalance = mToken.balanceOf(account);
                if (mTokenBalance == 0) {
                    continue;
                }

                uint redeemAmount = mTokenBalance / 2;

                (err, liquidity, shortfall) = comptroller
                    .getHypotheticalAccountLiquidity(
                        account,
                        address(mToken),
                        redeemAmount,
                        0
                    );
                assertEq(err, 0, "Error getting hypothetical liquidity");
                assertGt(
                    liquidity,
                    0,
                    "Account should maintain positive liquidity after hypothetical redemption"
                );
                assertEq(
                    shortfall,
                    0,
                    "Account should have no shortfall after hypothetical redemption"
                );
            }

            vm.stopPrank();
        }
    }

    function testLatestRoundDataRevertOnChainlinkPriceIsZero() public {
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(1))
        );

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint80(1), // roundId
                int256(0), // answer
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound
            )
        );

        vm.expectRevert("Chainlink price cannot be lower or equal to 0");
        wrapper.latestRoundData();
    }

    function testLatestRoundDataRevertOnIncompleteRoundState() public {
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(1))
        );

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
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

    function testLatestRoundDataRevertOnStalePriceData() public {
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(1))
        );

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint80(2), // roundId
                int256(3_000e8), // answer
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound - less than roundId to simulate stale price
            )
        );

        vm.expectRevert("Stale price");
        wrapper.latestRoundData();
    }

    function testNoUpdateEarlyReturnsPreviousRound() public {
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(uint256(2))
        );
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
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
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector
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

    function testSetMaxDecrements() public {
        uint8 newMaxDecrements = 15;
        uint8 originalMaxDecrements = wrapper.maxDecrements();

        // Non-owner should not be able to change maxDecrements
        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setMaxDecrements(newMaxDecrements);

        // Owner should be able to change maxDecrements
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit MaxDecrementsChanged(originalMaxDecrements, newMaxDecrements);
        wrapper.setMaxDecrements(newMaxDecrements);

        assertEq(
            wrapper.maxDecrements(),
            newMaxDecrements,
            "maxDecrements should be updated"
        );
        assertNotEq(
            wrapper.maxDecrements(),
            originalMaxDecrements,
            "maxDecrements should be different from original"
        );
    }

    function testMaxDecrementsLimit() public {
        // Mock the feed to return valid data for specific rounds
        uint256 latestRound = 100;

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(wrapper.originalFeed().latestRound.selector),
            abi.encode(latestRound)
        );

        // Set maxDecrements to 3 (shouldn't reach round 95)
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        wrapper.setMaxDecrements(3);

        // Mock valid price data for round 100 (latest)
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint80(latestRound),
                int256(1000),
                uint256(block.timestamp),
                uint256(block.timestamp),
                uint80(latestRound)
            )
        );

        // Should return latest price since we can't find valid price within 3 decrements
        (uint80 roundId, int256 answer, , , uint80 answeredInRound) = wrapper
            .latestRoundData();
        assertEq(
            answer,
            1000,
            "Should return latest price when valid price not found within maxDecrements"
        );
        assertEq(roundId, uint80(latestRound), "Should return latest round ID");
        assertEq(
            answeredInRound,
            uint80(latestRound),
            "Should return latest answered round"
        );

        // Set maxDecrements to 6 (should reach round 95)
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        wrapper.setMaxDecrements(6);

        // Mock valid price data for round 95
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector,
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
        assertEq(roundId, uint80(latestRound - 5), "Should return round 95 ID");
        assertEq(
            answeredInRound,
            uint80(latestRound - 5),
            "Should return round 95 as answered round"
        );
    }

    function testUpdatePriceEarlyFailsOnAddReserves() public {
        // Mock _addReserves to return error code 1 (failure)
        vm.mockCall(
            address(addresses.getAddress("MOONWELL_WETH")),
            abi.encodeWithSelector(MErc20._addReserves.selector),
            abi.encode(uint256(1))
        );

        // Set gas price higher than base fee to avoid underflow
        vm.fee(1 gwei);
        vm.txGasPrice(2 gwei);

        // Calculate required payment
        uint256 payment = (tx.gasprice - block.basefee) *
            uint256(wrapper.feeMultiplier());

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                latestRoundOnChain + 1,
                300e8,
                0,
                block.timestamp,
                latestRoundOnChain + 1
            )
        );
        vm.expectRevert("ChainlinkOEVWrapper: Failed to add reserves");
        wrapper.updatePriceEarly{value: payment}();
    }
}

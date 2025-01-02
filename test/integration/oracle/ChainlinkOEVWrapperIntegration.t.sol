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
    event FeeMultiplierChanged(uint16 newFee);
    event EarlyUpdateWindowChanged(uint256 newWindow);
    event ProtocolOEVRevenueUpdated(
        address indexed receiver,
        uint256 revenueAdded
    );
    event MaxDecrementsChanged(uint16 newMaxDecrements);

    ChainlinkFeedOEVWrapper public wrapper;
    Comptroller comptroller;
    MarketBase public marketBase;

    uint256 public constant multiplier = 99;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");

        super.setUp();
        vm.selectFork(primaryForkId);
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);

        wrapper = ChainlinkFeedOEVWrapper(
            addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER")
        );
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

        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(
                uint80(1), // roundId
                mockPrice, // answer
                uint256(0), // startedAt
                uint256(block.timestamp), // updatedAt
                uint80(1) // answeredInRound
            )
        );

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei
        vm.expectEmit(address(wrapper));
        emit ProtocolOEVRevenueUpdated(
            addresses.getAddress("MOONWELL_WETH"),
            tax
        );
        int256 price = wrapper.updatePriceEarly{value: tax}();

        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        vm.warp(vm.getBlockTimestamp() + 1);

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(mockPrice, price, "Price should be the same as price");
        assertEq(
            timestamp,
            block.timestamp - 1,
            "Timestamp should be the same as block.timestamp - 1"
        );
    }

    function testReturnOriginalFeedPriceIfEarlyUpdateWindowHasPassed() public {
        testCanUpdatePriceEarly();

        vm.warp(vm.getBlockTimestamp() + wrapper.earlyUpdateWindow());

        int256 mockPrice = 3_3333e8; // chainlink oracle uses 8 decimals
        uint256 mockTimestamp = block.timestamp - 1;
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(uint80(1), mockPrice, 0, mockTimestamp, uint80(1))
        );
        (, int256 answer, , uint256 timestamp, ) = wrapper.latestRoundData();

        assertEq(mockPrice, answer, "Price should be the same as answer");
        assertEq(
            timestamp,
            mockTimestamp,
            "Timestamp should be the same as block.timestamp"
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
            console.log("Liquidity:", liquidity);

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
                abi.encode(uint80(1), newPrice, 0, block.timestamp, uint80(1))
            );
            wrapper.updatePriceEarly{value: tax}();

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
        uint16 newMultiplier = 1;

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit FeeMultiplierChanged(newMultiplier);
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

    function testSetEarlyUpdateWindow() public {
        uint256 newWindow = 15;

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit EarlyUpdateWindowChanged(newWindow);
        wrapper.setEarlyUpdateWindow(newWindow);

        assertEq(
            wrapper.earlyUpdateWindow(),
            newWindow,
            "Early update window not updated"
        );
    }

    function testSetEarlyUpdateWindowRevertNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setEarlyUpdateWindow(15);
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

    function testUpdatePriceEarlyRevertOnChainlinkPriceIsZero() public {
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

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);

        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei

        vm.expectRevert("Chainlink price cannot be lower than 0");
        wrapper.updatePriceEarly{value: tax}();
    }

    function testUpdatePriceEearlyRevertOnIncompleteRoundState() public {
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

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei

        vm.expectRevert("Round is in incompleted state");
        wrapper.updatePriceEarly{value: tax}();
    }

    function testUpdatePriceEarlyRevertOnStalePriceData() public {
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

        uint256 tax = (50 gwei - 25 gwei) * multiplier; // (gasPrice - baseFee) * multiplier
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei); // Set gas price to 50 gwei
        vm.fee(25 gwei); // Set base fee to 25 gwei

        vm.expectRevert("Stale price");
        wrapper.updatePriceEarly{value: tax}();
    }

    function testLatestRoundDataRevertOnChainlinkPriceIsZero() public {
        // Ensure we're outside the early update window to force fetching from original feed
        vm.warp(block.timestamp + wrapper.earlyUpdateWindow() + 1);

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

        vm.expectRevert("Chainlink price cannot be lower than 0");
        wrapper.latestRoundData();
    }

    function testLatestRoundDataRevertOnIncompleteRoundState() public {
        // Ensure we're outside the early update window to force fetching from original feed
        vm.warp(block.timestamp + wrapper.earlyUpdateWindow() + 1);

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
        // Ensure we're outside the early update window to force fetching from original feed
        vm.warp(block.timestamp + wrapper.earlyUpdateWindow() + 1);

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
            1,
            "Answered in round should be the previous round"
        );
    }

    function testSetMaxDecrements() public {
        uint16 newMaxDecrements = 15;
        uint16 originalMaxDecrements = wrapper.maxDecrements();

        // Non-owner should not be able to change maxDecrements
        vm.prank(address(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setMaxDecrements(newMaxDecrements);

        // Owner should be able to change maxDecrements
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.expectEmit(address(wrapper));
        emit MaxDecrementsChanged(newMaxDecrements);
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

        // Mock valid price data for round 100 (latest)
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().getRoundData.selector,
                uint80(latestRound)
            ),
            abi.encode(
                uint80(latestRound),
                int256(1000),
                uint256(block.timestamp),
                uint256(block.timestamp),
                uint80(latestRound)
            )
        );

        // Mock invalid price data for rounds 99-96
        for (uint256 i = latestRound - 1; i >= latestRound - 4; i--) {
            vm.mockCall(
                address(wrapper.originalFeed()),
                abi.encodeWithSelector(
                    wrapper.originalFeed().getRoundData.selector,
                    uint80(i)
                ),
                abi.encode(
                    uint80(i),
                    int256(0),
                    uint256(0),
                    uint256(0),
                    uint80(i)
                )
            );
        }

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

        // Set maxDecrements to 3 (shouldn't reach round 95)
        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        wrapper.setMaxDecrements(3);

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
}

pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract ChainlinkOEVWrapperIntegrationTest is PostProposalCheck {
    event PriceUpdated(int256 newPrice);
    event FeeMultiplierChanged(uint16 newFee);
    event EarlyUpdateWindowChanged(uint256 newWindow);

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
        emit PriceUpdated(mockPrice);
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
        uint256 wethBalanceBefore = IERC20(addresses.getAddress("WETH"))
            .balanceOf(addresses.getAddress("MOONWELL_WETH"));

        uint256 tax = 25 gwei * multiplier;
        vm.deal(address(this), tax);

        vm.txGasPrice(50 gwei);
        vm.fee(25 gwei);
        wrapper.updatePriceEarly{value: tax}();

        assertEq(
            wethBalanceBefore + tax,
            IERC20(addresses.getAddress("WETH")).balanceOf(
                addresses.getAddress("MOONWELL_WETH")
            ),
            "WETH balance should be increased by tax"
        );
    }
}

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
        // Setup test user and initial conditions
        address user = address(0x1234);
        MToken mToken = MToken(addresses.getAddress("MOONWELL_WETH"));

        // Get max supply amount and supply collateral
        uint256 mintAmount = marketBase.getMaxSupplyAmount(mToken);
        _mintMToken(user, address(mToken), mintAmount);

        // Enter markets for the user
        vm.startPrank(user);
        address[] memory markets = new address[](1);
        markets[0] = address(mToken);
        comptroller.enterMarkets(markets);
        vm.stopPrank();

        // Borrow maximum allowed amount
        uint256 borrowAmount = marketBase.getMaxUserBorrowAmount(mToken, user);
        vm.prank(user);
        MErc20Delegator(payable(address(mToken))).borrow(borrowAmount);

        (, int256 priceBefore, , , ) = wrapper.latestRoundData();

        console.log("priceBefore", uint256(priceBefore));
        uint256 tax = (50 gwei - 25 gwei) * uint256(wrapper.feeMultiplier());
        vm.deal(address(this), tax);
        vm.txGasPrice(50 gwei);
        vm.fee(25 gwei);

        // Update price to make position underwater (50% price drop)
        int256 newPrice = priceBefore / 2;
        console.log("new price", uint256(newPrice));
        vm.mockCall(
            address(wrapper.originalFeed()),
            abi.encodeWithSelector(
                wrapper.originalFeed().latestRoundData.selector
            ),
            abi.encode(uint80(1), newPrice, 0, block.timestamp, uint80(1))
        );
        wrapper.updatePriceEarly{value: tax}();

        {
            // Verify user is now underwater
            (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
                .getHypotheticalAccountLiquidity(user, address(mToken), 0, 0);

            assertEq(err, 0, "Error in hypothetical liquidity calculation");
            assertEq(liquidity, 0, "Liquidity should be 0");
            assertGt(shortfall, 0, "Position should be underwater");
        }

        // Setup liquidator
        address liquidator = address(0x5678);
        uint256 repayAmount = borrowAmount / 2;
        deal(MErc20(address(mToken)).underlying(), liquidator, repayAmount);

        // Execute liquidation
        vm.startPrank(liquidator);
        IERC20(MErc20(address(mToken)).underlying()).approve(
            address(mToken),
            repayAmount
        );
        assertEq(
            MErc20Delegator(payable(address(mToken))).liquidateBorrow(
                user,
                repayAmount,
                MErc20(address(mToken))
            ),
            0,
            "Liquidation failed"
        );
        vm.stopPrank();
    }
}

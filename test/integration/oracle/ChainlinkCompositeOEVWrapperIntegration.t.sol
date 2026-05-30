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
import {ChainlinkCompositeOEVWrapper} from "@protocol/oracles/ChainlinkCompositeOEVWrapper.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {LiquidationData, Liquidations, LiquidationState} from "@test/utils/Liquidations.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";

contract ChainlinkCompositeOEVWrapperIntegrationTest is
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

    ChainlinkCompositeOEVWrapper[] public wrappers;
    Comptroller comptroller;
    MarketBase public marketBase;
    OEVProtocolFeeRedeemer public redeemer;

    function setUp() public override {
        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");

        super.setUp();
        vm.selectFork(primaryForkId);
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);

        // Resolve composite wrappers from configurations
        CompositeOracleConfig[]
            memory compositeConfigs = getCompositeOracleConfigurations(
                block.chainid
            );
        for (uint256 i = 0; i < compositeConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(
                    compositeConfigs[i].compositeOracleName,
                    "_OEV_WRAPPER"
                )
            );
            if (addresses.isAddressSet(wrapperName)) {
                ChainlinkCompositeOEVWrapper wrapper = ChainlinkCompositeOEVWrapper(
                        payable(addresses.getAddress(wrapperName))
                    );
                wrappers.push(wrapper);
                vm.makePersistent(address(wrapper));
            }
        }

        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));
        vm.makePersistent(address(oracle));

        if (addresses.isAddressSet("OEV_PROTOCOL_FEE_REDEEMER")) {
            redeemer = OEVProtocolFeeRedeemer(
                payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
            );
            vm.makePersistent(address(redeemer));
        }
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
        ChainlinkCompositeOEVWrapper wrapper
    ) internal pure returns (address) {
        return _perWrapperActor("BORROWER", address(wrapper));
    }

    function _liquidator(
        ChainlinkCompositeOEVWrapper wrapper
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

    // ==================== Delay Mechanism Tests ====================

    function testReturnFreshPriceWhenBaseRoundUnchanged() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            // Base round hasn't changed -> should return fresh composite price
            (, int256 answer, , uint256 updatedAt, ) = wrapper
                .latestRoundData();

            assertGt(answer, 0, "Price should be positive");
            assertGt(updatedAt, 0, "Timestamp should be positive");
        }
    }

    function testReturnCachedPriceWhenNewBaseRoundWithinDelay() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            // Get current cached price
            int256 cachedPrice = wrapper.cachedCompositePrice();

            // Get current base round
            uint256 currentBaseRound = wrapper.baseFeed().latestRound();

            // Mock base feed to advance to next round (new price info)
            vm.mockCall(
                address(wrapper.baseFeed()),
                abi.encodeWithSelector(
                    wrapper.baseFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(currentBaseRound + 1),
                    int256(3100e8),
                    uint256(0),
                    block.timestamp,
                    uint80(currentBaseRound + 1)
                )
            );

            // Within delay window -> should return cached composite price
            (, int256 answer, , , ) = wrapper.latestRoundData();

            assertEq(
                answer,
                cachedPrice,
                "Should return cached composite price"
            );
        }
    }

    function testReturnFreshPriceWhenDelayExpired() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            uint256 currentBaseRound = wrapper.baseFeed().latestRound();
            uint256 originalTimestamp = block.timestamp;

            // Mock base feed to advance to next round
            vm.mockCall(
                address(wrapper.baseFeed()),
                abi.encodeWithSelector(
                    wrapper.baseFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(currentBaseRound + 1),
                    int256(3100e8),
                    uint256(0),
                    originalTimestamp,
                    uint80(currentBaseRound + 1)
                )
            );

            // Warp past delay
            vm.warp(originalTimestamp + wrapper.maxRoundDelay());

            // Past delay -> should return fresh composite price
            (, int256 answer, , , ) = wrapper.latestRoundData();

            assertGt(answer, 0, "Should return fresh positive price");
        }
    }

    // ==================== Configuration Tests ====================

    function testSetLiquidatorFeeBps() public {
        uint16 newMultiplier = 100;
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];
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
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];
            vm.expectRevert("Ownable: caller is not the owner");
            wrapper.setLiquidatorFeeBps(1);
        }
    }

    // ==================== Price Validation Tests ====================

    function testLatestRoundDataRevertOnZeroCompositePrice() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            // Mock composite oracle to return 0 price
            vm.mockCall(
                address(wrapper.compositeOracle()),
                abi.encodeWithSelector(
                    wrapper.compositeOracle().latestRoundData.selector
                ),
                abi.encode(
                    uint80(0),
                    int256(0),
                    uint256(0),
                    block.timestamp,
                    uint80(0)
                )
            );

            vm.expectRevert("Chainlink price cannot be lower or equal to 0");
            wrapper.latestRoundData();
        }
    }

    function testGetRoundDataReverts() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            vm.expectRevert(
                bytes(
                    "ChainlinkCompositeOEVWrapper: getRoundData not supported for composite oracles"
                )
            );
            wrapper.getRoundData(1);
        }
    }

    // ==================== Oracle Feed Validation ====================

    function testAllCompositeOraclesReturnValidPrice() public view {
        ChainlinkOracle oracle = ChainlinkOracle(address(comptroller.oracle()));

        CompositeOracleConfig[]
            memory compositeConfigs = getCompositeOracleConfigurations(
                block.chainid
            );

        for (uint256 i = 0; i < compositeConfigs.length; i++) {
            string memory mTokenKey = compositeConfigs[i].mTokenKey;
            if (!addresses.isAddressSet(mTokenKey)) continue;

            address mTokenAddr = addresses.getAddress(mTokenKey);
            uint256 price = oracle.getUnderlyingPrice(MToken(mTokenAddr));

            assertTrue(
                price > 0,
                string(
                    abi.encodePacked(
                        "Oracle price is 0 for ",
                        compositeConfigs[i].symbol
                    )
                )
            );
        }
    }

    // ==================== Liquidation Tests ====================

    function testUpdatePriceEarlyAndLiquidate_RevertZeroRepay() public {
        CompositeOracleConfig[]
            memory compositeConfigs = getCompositeOracleConfigurations(
                block.chainid
            );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];
            string memory mTokenKey = compositeConfigs[i].mTokenKey;
            if (!addresses.isAddressSet(mTokenKey)) continue;

            address mTokenAddr = addresses.getAddress(mTokenKey);
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
        CompositeOracleConfig[]
            memory compositeConfigs = getCompositeOracleConfigurations(
                block.chainid
            );
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];
            string memory mTokenKey = compositeConfigs[i].mTokenKey;
            if (!addresses.isAddressSet(mTokenKey)) continue;

            address mTokenAddr = addresses.getAddress(mTokenKey);
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
            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                address(0xBEEF),
                1,
                address(0),
                address(0xBEEF)
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_Succeeds() public {
        CompositeOracleConfig[]
            memory compositeConfigs = getCompositeOracleConfigurations(
                block.chainid
            );

        for (uint256 i = 0; i < wrappers.length; i++) {
            vm.clearMockedCalls();

            ChainlinkCompositeOEVWrapper wrapper = wrappers[i];

            string memory mTokenKey = compositeConfigs[i].mTokenKey;
            if (!addresses.isAddressSet(mTokenKey)) continue;

            address mTokenCollateralAddr = addresses.getAddress(mTokenKey);

            // Use USDC as borrow token
            address mTokenBorrowAddr = addresses.getAddress("MOONWELL_USDC");

            address borrower = _borrower(wrapper);
            address liquidator = _liquidator(wrapper);

            (, uint256 borrowAmount) = _setupSyntheticPosition(
                mTokenCollateralAddr,
                mTokenBorrowAddr,
                borrower
            );

            // Crash price for liquidation
            _crashPriceForLiquidation(wrapper, borrower);

            // Execute liquidation
            uint256 repayAmount = borrowAmount / 10;
            address borrowUnderlying = MErc20(mTokenBorrowAddr).underlying();
            deal(borrowUnderlying, liquidator, repayAmount * 2);

            vm.startPrank(liquidator);
            IERC20(borrowUnderlying).approve(address(wrapper), repayAmount);

            wrapper.updatePriceEarlyAndLiquidate(
                borrower,
                repayAmount,
                mTokenCollateralAddr,
                mTokenBorrowAddr
            );
            vm.stopPrank();
        }
    }

    // ==================== Helper Functions ====================

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

    function _calculateSyntheticAmounts(
        address mTokenCollateralAddr,
        address mTokenBorrowAddr
    ) internal view returns (uint256 collateralAmount, uint256 borrowAmount) {
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

    function _crashPriceForLiquidation(
        ChainlinkCompositeOEVWrapper wrapper,
        address borrower
    ) internal {
        (, int256 price, , , ) = wrapper.latestRoundData();
        int256 crashedPrice = (price * 40) / 100; // 60% price drop

        // Mock composite oracle to return crashed price
        vm.mockCall(
            address(wrapper.compositeOracle()),
            abi.encodeWithSelector(
                wrapper.compositeOracle().latestRoundData.selector
            ),
            abi.encode(
                uint80(0),
                crashedPrice,
                uint256(0),
                block.timestamp,
                uint80(0)
            )
        );

        // Verify position is underwater
        (uint256 err, , uint256 shortfall) = comptroller.getAccountLiquidity(
            borrower
        );
        require(err == 0 && shortfall > 0, "position not underwater");
    }
}

pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {IMorphoBlue} from "@protocol/morpho/IMorphoBlue.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {IMetaMorpho, MarketParams, MarketAllocation} from "@protocol/morpho/IMetaMorpho.sol";
import {ChainlinkOracleConfigs} from "@proposals/ChainlinkOracleConfigs.sol";
import {OEVProtocolFeeRedeemer} from "@protocol/OEVProtocolFeeRedeemer.sol";
import {IMorphoChainlinkOracleV2} from "@protocol/morpho/IMorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

contract ChainlinkOEVMorphoWrapperIntegrationTest is
    PostProposalCheck,
    ChainlinkOracleConfigs
{
    event LiquidatorFeeBpsChanged(
        uint16 oldLiquidatorFeeBps,
        uint16 newLiquidatorFeeBps
    );
    event PriceUpdatedEarlyAndLiquidated(
        address indexed sender,
        address indexed borrower,
        uint256 seizedAssets,
        uint256 repaidAssets,
        uint256 fee
    );

    ChainlinkOEVMorphoWrapper[] public wrappers;
    /// @notice Parallel array of canonical (approved) MarketParams per wrapper.
    ///         Mirrors `mip-x56.sol::_canonicalMorphoMarket` so revert-path
    ///         tests can drive each wrapper past its `approvedMarkets` gate
    ///         and reach the intended downstream revert.
    MarketParams[] internal approvedParams;
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

        // Get redeemer contract from addresses
        redeemer = OEVProtocolFeeRedeemer(
            payable(addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER"))
        );

        // Resolve morpho wrappers from shared morpho oracle configurations
        MorphoOracleConfig[]
            memory morphoConfigs = getMorphoOracleConfigurations(block.chainid);
        for (uint256 i = 0; i < morphoConfigs.length; i++) {
            string memory wrapperName = string(
                abi.encodePacked(morphoConfigs[i].proxyName, "_ORACLE_PROXY")
            );
            if (addresses.isAddressSet(wrapperName)) {
                wrappers.push(
                    ChainlinkOEVMorphoWrapper(addresses.getAddress(wrapperName))
                );
                approvedParams.push(
                    _canonicalParamsFor(morphoConfigs[i].proxyName)
                );
            }
        }
    }

    /// @notice Mirrors `mip-x56.sol::_canonicalMorphoMarket` — returns the
    ///         canonical MarketParams that MIP-X56 seeded as approved for
    ///         each Morpho wrapper proxy. Tests use this to drive the
    ///         wrapper past its `approvedMarkets` gate.
    function _canonicalParamsFor(
        string memory proxyName
    ) internal view returns (MarketParams memory) {
        address loanToken = addresses.getAddress("USDC");
        address irm = addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM");

        bytes32 key = keccak256(bytes(proxyName));
        if (key == keccak256(bytes("CHAINLINK_WELL_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("xWELL_PROXY"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_WELL_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.625e18
                });
        } else if (key == keccak256(bytes("CHAINLINK_MAMO_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("MAMO"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_MAMO_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.385e18
                });
        } else if (key == keccak256(bytes("CHAINLINK_stkWELL_USD"))) {
            return
                MarketParams({
                    loanToken: loanToken,
                    collateralToken: addresses.getAddress("STK_GOVTOKEN_PROXY"),
                    oracle: addresses.getAddress(
                        "MORPHO_CHAINLINK_stkWELL_USD_ORACLE"
                    ),
                    irm: irm,
                    lltv: 0.625e18
                });
        }
        revert(
            string.concat(
                "ChainlinkOEVMorphoWrapperIntegrationTest: no canonical params for ",
                proxyName
            )
        );
    }

    function testSetLiquidatorFeeBps() public {
        uint16 newMultiplier = 100; // 1%
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
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
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            vm.expectRevert("Ownable: caller is not the owner");
            wrapper.setLiquidatorFeeBps(1);
        }
    }

    function testGetRoundData() public {
        uint80 roundId = 1;
        int256 mockPrice = 3_000e8;
        uint256 mockTimestamp = block.timestamp;
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
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

            assertEq(returnedRoundId, roundId);
            assertEq(answer, mockPrice);
            assertEq(startedAt, 0);
            assertEq(updatedAt, mockTimestamp);
            assertEq(answeredInRound, roundId);
        }
    }

    function testLatestRoundDataRevertOnChainlinkPriceIsZero() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            uint256 ts = vm.getBlockTimestamp();
            vm.warp(ts + uint256(wrapper.maxRoundDelay()));
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(uint80(1), int256(0), uint256(0), ts, uint80(1))
            );
            vm.expectRevert();
            wrapper.latestRoundData();
        }
    }

    function testLatestRoundDataRevertOnIncompleteRoundState() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
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
            vm.expectRevert();
            wrapper.latestRoundData();
        }
    }

    function testLatestRoundDataRevertOnStalePriceData() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            uint256 ts = vm.getBlockTimestamp();
            vm.warp(ts + uint256(wrapper.maxRoundDelay()));
            vm.mockCall(
                address(wrapper.priceFeed()),
                abi.encodeWithSelector(
                    wrapper.priceFeed().latestRoundData.selector
                ),
                abi.encode(
                    uint80(2),
                    int256(3_000e8),
                    uint256(0),
                    ts,
                    uint80(1)
                )
            );
            vm.expectRevert();
            wrapper.latestRoundData();
        }
    }

    function testUpdatePriceEarlyAndLiquidate_WELL() public {
        _testLiquidation(
            addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY"),
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("MORPHO_CHAINLINK_WELL_USD_ORACLE"),
            0.625e18,
            1_000_000e18, // 1M WELL tokens (~$10k at $0.01)
            10_000e18
        );
    }

    function testUpdatePriceEarlyAndLiquidate_stkWELL() public {
        _testLiquidation(
            addresses.getAddress("CHAINLINK_stkWELL_USD_ORACLE_PROXY"),
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            addresses.getAddress("MORPHO_CHAINLINK_stkWELL_USD_ORACLE"),
            0.625e18,
            1_000_000e18, // 1M stkWELL tokens
            10_000e18
        );
    }

    function testUpdatePriceEarlyAndLiquidate_MAMO() public {
        _testLiquidation(
            addresses.getAddress("CHAINLINK_MAMO_USD_ORACLE_PROXY"),
            addresses.getAddress("MAMO"),
            addresses.getAddress("MORPHO_CHAINLINK_MAMO_USD_ORACLE"),
            0.385e18,
            250_000e18, // Scale up collateral (5x from 50k to match WELL's economic value)
            2_500e18 // Scale up seized amount proportionally (MAMO is 4x WELL price, so 10k/4 = 2.5k)
        );
    }

    function _testLiquidation(
        address wrapperAddr,
        address collToken,
        address oracleAddr,
        uint256 lltv,
        uint256 collateralAmount,
        uint256 seized
    ) internal {
        ChainlinkOEVMorphoWrapper wrapper = ChainlinkOEVMorphoWrapper(
            wrapperAddr
        );
        address loanToken = addresses.getAddress("USDC");
        uint256 borrowAmount = 50e6; // $50 USDC (6 decimals)

        // Setup market params
        MarketParams memory params = MarketParams({
            loanToken: loanToken,
            collateralToken: collToken,
            oracle: oracleAddr,
            irm: addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM"),
            lltv: lltv
        });

        // Setup Morpho Blue
        IMorphoBlue morpho = IMorphoBlue(addresses.getAddress("MORPHO_BLUE"));

        _supplyLiquidityAndBorrow(
            morpho,
            params,
            loanToken,
            collToken,
            borrowAmount,
            collateralAmount
        );

        // Mock price crash
        vm.mockCall(
            address(wrapper.priceFeed()),
            abi.encodeWithSelector(bytes4(keccak256("latestRoundData()"))),
            abi.encode(
                uint80(777),
                int256(1),
                uint256(0),
                block.timestamp,
                uint80(777)
            )
        );

        // Execute liquidation
        _executeLiquidation(
            wrapper,
            params,
            loanToken,
            borrowAmount,
            seized,
            collToken
        );
    }

    function _supplyLiquidityAndBorrow(
        IMorphoBlue morpho,
        MarketParams memory params,
        address loanToken,
        address collToken,
        uint256 borrowAmount,
        uint256 collateralAmount
    ) private {
        // Supply USDC liquidity so there's enough to borrow
        address supplier = address(uint160(uint256(keccak256("SUPPLIER"))));
        deal(loanToken, supplier, borrowAmount * 10);
        vm.startPrank(supplier);
        IERC20(loanToken).approve(address(morpho), borrowAmount * 10);
        morpho.supply(params, borrowAmount * 10, 0, supplier, "");
        vm.stopPrank();

        // Setup borrower position
        deal(collToken, BORROWER, collateralAmount);
        vm.startPrank(BORROWER);
        IERC20(collToken).approve(address(morpho), collateralAmount);
        morpho.supplyCollateral(params, collateralAmount, BORROWER, "");
        morpho.borrow(params, borrowAmount, 0, BORROWER, BORROWER);
        vm.stopPrank();
    }

    function _executeLiquidation(
        ChainlinkOEVMorphoWrapper wrapper,
        MarketParams memory params,
        address loanToken,
        uint256 borrowAmount,
        uint256 seized,
        address collToken
    ) internal {
        // Fund the liquidator with 2x borrowAmount so we can pass a
        // maxRepayAmount larger than the actual debt and exercise both the
        // HAL-08 allowance-scrub path and the HAL-03 excess-refund path
        // (any unused loan tokens must be returned via safeTransfer).
        uint256 maxRepayAmount = borrowAmount * 2;
        deal(loanToken, LIQUIDATOR, maxRepayAmount);
        vm.startPrank(LIQUIDATOR);
        IERC20(loanToken).approve(address(wrapper), maxRepayAmount);

        uint256 liqLoanBefore = IERC20(loanToken).balanceOf(LIQUIDATOR);
        uint256 liqCollBefore = IERC20(collToken).balanceOf(LIQUIDATOR);
        uint256 redeemerCollBefore = IERC20(collToken).balanceOf(
            address(redeemer)
        );

        // snapshot so we can assert the fresh round is not persisted globally after the liquidation.
        uint256 cachedRoundIdBefore = wrapper.cachedRoundId();

        vm.recordLogs();
        wrapper.updatePriceEarlyAndLiquidate(
            params,
            BORROWER,
            seized,
            maxRepayAmount
        );
        vm.stopPrank();

        // HAL-08: residual loan-token allowance to Morpho Blue must be 0
        // after the call. If a future regression dropped the forceApprove(.,0)
        // scrub, a subsequent caller could re-use the leftover allowance.
        assertEq(
            IERC20(loanToken).allowance(
                address(wrapper),
                address(wrapper.morphoBlue())
            ),
            0,
            "HAL-08: residual loan-token allowance to morphoBlue not zeroed"
        );

        // HAL-03: every unused loan token must be returned to msg.sender
        // (the liquidator). Combined with the deal of `maxRepayAmount`, the
        // liquidator's net spend equals exactly `actualRepaidAssets`.
        uint256 liqLoanSpent = liqLoanBefore -
            IERC20(loanToken).balanceOf(LIQUIDATOR);
        assertLe(
            liqLoanSpent,
            borrowAmount,
            "HAL-03: liquidator spent more loan tokens than the debt"
        );

        // Parse event for split amounts and the actual seized collateral.
        (
            uint256 actualSeizedAssets,
            uint256 protocolFee,
            uint256 liquidatorFee
        ) = _parseLiquidationEventFull();

        // Assertions
        // the fresh round (777) priced this liquidation but must not persist globally.
        assertTrue(
            cachedRoundIdBefore != 777,
            "precondition: fresh round must differ from the cached round"
        );
        assertEq(
            wrapper.cachedRoundId(),
            cachedRoundIdBefore,
            "cachedRoundId must not advance globally after liquidation"
        );
        assertGt(
            liqLoanBefore - IERC20(loanToken).balanceOf(LIQUIDATOR),
            0,
            "no loan repaid"
        );
        uint256 liquidatorReceived = IERC20(collToken).balanceOf(LIQUIDATOR) -
            liqCollBefore;
        assertGt(liquidatorReceived, 0, "no collateral received");

        // Invariant: every collateral token seized must end up either with
        // the liquidator or with the redeemer (protocol). No tokens stuck.
        assertEq(
            liquidatorFee + protocolFee,
            actualSeizedAssets,
            "split conservation: liquidatorFee + protocolFee != seized"
        );
        // The on-chain transfer split must match the event split exactly.
        assertEq(
            liquidatorReceived,
            liquidatorFee,
            "liquidator on-chain receipt != event liquidatorFee"
        );

        // Verify redeemer received protocol fee (underlying tokens)
        uint256 redeemerCollAfter = IERC20(collToken).balanceOf(
            address(redeemer)
        );
        if (protocolFee > 0) {
            assertGt(
                redeemerCollAfter,
                redeemerCollBefore,
                "Redeemer should receive protocol fee"
            );
            assertEq(
                redeemerCollAfter - redeemerCollBefore,
                protocolFee,
                "Redeemer balance should match protocol fee from event"
            );

            // Directional split check: with liquidatorFeeBps = 4000 (40%),
            // the liquidator receives the full repayment value PLUS 40% of
            // the collateral surplus, while the protocol receives only 60%
            // of the surplus. So whenever the protocol gets any fee at all,
            // the liquidator's share must strictly dominate.
            assertGt(
                liquidatorFee,
                protocolFee,
                "liquidatorFee should exceed protocolFee when protocolFee > 0"
            );

            address mTokenCollateral = _findMTokenForUnderlying(collToken);
            if (
                mTokenCollateral != address(0) &&
                redeemer.whitelistedMarkets(mTokenCollateral)
            ) {
                _addReservesAndVerify(mTokenCollateral);
            } else {
                console2.log(
                    "No mToken market found or not whitelisted for collateral token",
                    IERC20(collToken).symbol()
                );
            }
        } else {
            // When protocolFee is 0, redeemer should not receive any tokens
            assertEq(
                redeemerCollAfter,
                redeemerCollBefore,
                "Redeemer should not receive tokens when protocolFee is 0"
            );
            // protocolFee == 0 is the collateral-worth-less-than-repay case;
            // the liquidator must have received 100% of the seized collateral.
            assertEq(
                liquidatorFee,
                actualSeizedAssets,
                "liquidator should receive full seized when protocolFee is 0"
            );
        }
    }

    /// @notice Parse PriceUpdatedEarlyAndLiquidated for all numeric fields.
    /// @dev Mirrors `_parseLiquidationEvent` but also returns `seizedAssets`
    ///      so callers can verify split conservation.
    function _parseLiquidationEventFull()
        internal
        returns (
            uint256 seizedAssets,
            uint256 protocolFee,
            uint256 liquidatorFee
        )
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256(
            "PriceUpdatedEarlyAndLiquidated(address,uint256,uint256,uint256,uint256)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                (
                    uint256 _seized,
                    ,
                    uint256 _protocolFee,
                    uint256 _liquidatorFee
                ) = abi.decode(
                        logs[i].data,
                        (uint256, uint256, uint256, uint256)
                    );

                seizedAssets = _seized;
                protocolFee = _protocolFee;
                liquidatorFee = _liquidatorFee;
            }
        }
    }

    /// @notice Parse liquidation event to extract fees
    function _parseLiquidationEvent()
        internal
        returns (uint256 protocolFee, uint256 liquidatorFee)
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSig = keccak256(
            "PriceUpdatedEarlyAndLiquidated(address,uint256,uint256,uint256,uint256)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSig) {
                (, , uint256 _protocolFee, uint256 _liquidatorFee) = abi.decode(
                    logs[i].data,
                    (uint256, uint256, uint256, uint256)
                );

                protocolFee = _protocolFee;
                liquidatorFee = _liquidatorFee;
            }
        }
    }

    /// @notice Find mToken address for a given underlying token
    /// @param underlyingToken The underlying token address
    /// @return mToken The mToken address, or address(0) if not found
    function _findMTokenForUnderlying(
        address underlyingToken
    ) internal view returns (address mToken) {
        // Try common mToken names based on token symbol
        string memory symbol = IERC20(underlyingToken).symbol();

        // Map common symbols to mToken address keys
        string memory mTokenKey = string(abi.encodePacked("MOONWELL_", symbol));

        if (addresses.isAddressSet(mTokenKey)) {
            return addresses.getAddress(mTokenKey);
        }
        return address(0);
    }

    /// @notice Add reserves from underlying token balance and verify
    /// @param mTokenCollateralAddr Address of the collateral mToken
    function _addReservesAndVerify(address mTokenCollateralAddr) internal {
        uint256 reservesBefore = MErc20(mTokenCollateralAddr).totalReserves();
        redeemer.addReserves(mTokenCollateralAddr);
        uint256 reservesAfter = MErc20(mTokenCollateralAddr).totalReserves();

        // Verify reserves increased after adding
        assertGt(
            reservesAfter,
            reservesBefore,
            "Reserves should increase after adding protocol fees"
        );

        // Verify redeemer no longer has underlying tokens
        address underlying = MErc20(mTokenCollateralAddr).underlying();
        assertEq(
            IERC20(underlying).balanceOf(address(redeemer)),
            0,
            "Redeemer should have no underlying tokens after adding reserves"
        );
    }

    function testUpdatePriceEarlyAndLiquidate_RevertArgsZero() public {
        MarketParams memory params;
        address mUSDC = addresses.getAddress("MOONWELL_USDC");
        address mWETH = addresses.getAddress("MOONWELL_WETH");
        params.loanToken = MErc20(mUSDC).underlying();
        params.collateralToken = MErc20(mWETH).underlying();
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(params, address(0), 1, 1);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 0, 1);
            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 1, 0);
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertInvalidPrice() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            MarketParams memory params = approvedParams[i];
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
            // Tight assertion: must revert at _validateRoundData, not earlier.
            vm.expectRevert("Chainlink price cannot be lower or equal to 0");
            wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 1, 1);
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertIncompleteRound() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            MarketParams memory params = approvedParams[i];
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
            vm.expectRevert("Round is in incompleted state");
            wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 1, 1);
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertStalePrice() public {
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            MarketParams memory params = approvedParams[i];
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
            vm.expectRevert("Stale price");
            wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 1, 1);
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertUnapprovedMarket() public {
        // Sanity: with `params.oracle = 0` and `lltv = 0`, the market id is
        // not in `approvedMarkets`, so the gate must fire and reject. This
        // is the test the four revert tests above used to accidentally hit.
        MarketParams memory params;
        params.loanToken = addresses.getAddress("USDC");
        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            _mockValidRound(wrapper, 10, 3_000e8);
            vm.expectRevert("ChainlinkOEVMorphoWrapper: market not approved");
            wrapper.updatePriceEarlyAndLiquidate(
                params,
                address(0xBEEF),
                1 ether,
                1
            );
        }
    }

    function testUpdatePriceEarlyAndLiquidate_RevertLoanTokenTransferFailed()
        public
    {
        MarketParams memory params;
        address mUSDC = addresses.getAddress("MOONWELL_USDC");
        address mWETH = addresses.getAddress("MOONWELL_WETH");
        address loanToken = MErc20(mUSDC).underlying();
        params.loanToken = loanToken;
        params.collateralToken = MErc20(mWETH).underlying();
        params.oracle = addresses.getAddress(
            "MORPHO_CHAINLINK_WELL_USD_ORACLE"
        );
        params.irm = addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM");
        params.lltv = 0.625e18;

        for (uint256 i = 0; i < wrappers.length; i++) {
            ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
            _mockValidRound(wrapper, 10, 3_000e8);

            uint256 maxRepayAmount = 100e6;

            vm.mockCallRevert(
                loanToken,
                abi.encodeWithSignature(
                    "transferFrom(address,address,uint256)",
                    address(this),
                    address(wrapper),
                    maxRepayAmount
                ),
                abi.encodeWithSignature("Error(string)", "transfer failed")
            );

            vm.expectRevert();
            wrapper.updatePriceEarlyAndLiquidate(
                params,
                address(0xBEEF),
                1 ether, // seizedAssets
                maxRepayAmount
            );
        }
    }

    function _mockValidRound(
        ChainlinkOEVMorphoWrapper wrapper,
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

    /// @notice Regression: verify the per-market QUOTE_FEED_1 — which the
    ///         wrapper now reads directly for the loan-token price — is a
    ///         live raw Chainlink aggregator returning a positive answer.
    function testLoanFeedQuoteFeed1IsLiveRawAggregator() public {
        if (block.chainid != 8453) return;

        // WELL/USDC Morpho market on Base.
        address morphoOracle = 0x71FBaD6c2200C8A5B89380f9B6bb8a35d411c852;
        AggregatorV3Interface quoteFeed = IMorphoChainlinkOracleV2(morphoOracle)
            .QUOTE_FEED_1();
        require(address(quoteFeed) != address(0), "QUOTE_FEED_1 unset");
        _assertHasCode(address(quoteFeed), "QUOTE_FEED_1");
        (, int256 ans, , uint256 updatedAt, ) = quoteFeed.latestRoundData();
        require(ans > 0, "QUOTE_FEED_1 answer <= 0");
        require(updatedAt > 0, "QUOTE_FEED_1 updatedAt == 0");
    }

    function _assertHasCode(address target, string memory label) internal view {
        uint256 codeLen;
        assembly {
            codeLen := extcodesize(target)
        }
        require(codeLen > 0, string(abi.encodePacked(label, " has no code")));
    }
}

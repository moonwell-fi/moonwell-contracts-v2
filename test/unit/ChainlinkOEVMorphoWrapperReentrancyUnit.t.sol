// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";
import {IMorphoChainlinkOracleV2} from "@protocol/morpho/IMorphoChainlinkOracleV2.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockERC20Decimals} from "@test/mock/MockERC20Decimals.sol";

/// @notice Malicious Morpho Blue mock whose `liquidate()` re-enters the
///         wrapper. Used to prove the inline `nonReentrant` guard rejects
///         the second call before any state change.
contract ReentrantMorphoBlue {
    ChainlinkOEVMorphoWrapper public wrapper;
    MarketParams public reentryParams;

    function setReentryTarget(
        address _wrapper,
        MarketParams calldata _params
    ) external {
        wrapper = ChainlinkOEVMorphoWrapper(_wrapper);
        reentryParams = _params;
    }

    function liquidate(
        MarketParams memory,
        address,
        uint256,
        uint256,
        bytes memory
    ) external returns (uint256, uint256) {
        // Re-enter the wrapper through the same outer entry point. The
        // inline guard must trip on the second call and revert.
        wrapper.updatePriceEarlyAndLiquidate(
            reentryParams,
            address(0xBEEF),
            1,
            1
        );
        return (0, 0); // unreachable
    }
}

/// @notice Unit test for the inline `nonReentrant` guard on
///         `updatePriceEarlyAndLiquidate`. The guard is hand-rolled (not
///         inherited from OZ) because inheriting `ReentrancyGuardUpgradeable`
///         would shift all upgradeable storage slots, so its behavior is
///         not covered by the OZ test suite and needs its own regression.
contract ChainlinkOEVMorphoWrapperReentrancyUnitTest is Test {
    address internal owner = address(0xA11CE);
    address internal proxyAdmin = address(0xAD317);
    address internal feeRecipient = address(0xFEE);
    address internal chainlinkOracle = address(0xCAFE);

    MockChainlinkOracle internal priceFeed;
    MockERC20Decimals internal loanToken;
    MockERC20Decimals internal collateralToken;
    ReentrantMorphoBlue internal evilMorpho;
    address internal morphoOracle = address(0xB00B);

    ChainlinkOEVMorphoWrapper internal wrapper;

    function setUp() public {
        priceFeed = new MockChainlinkOracle(1e8, 8);
        priceFeed.set(1, 1e8, 1, block.timestamp, 1);

        loanToken = new MockERC20Decimals("Loan", "LOAN", 18);
        collateralToken = new MockERC20Decimals("Coll", "COLL", 18);
        evilMorpho = new ReentrantMorphoBlue();

        ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            proxyAdmin,
            ""
        );
        wrapper = ChainlinkOEVMorphoWrapper(address(proxy));
        wrapper.initializeV2(
            address(priceFeed),
            owner,
            address(evilMorpho),
            chainlinkOracle,
            feeRecipient,
            500,
            3600,
            10
        );

        // Stub the per-market Morpho oracle so BASE_FEED_1 == wrapper and
        // the chained-feed guards short-circuit on the inner re-entry too.
        vm.mockCall(
            morphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.BASE_FEED_1.selector
            ),
            abi.encode(address(wrapper))
        );
    }

    function _params() internal view returns (MarketParams memory p) {
        p = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: morphoOracle,
            irm: address(0),
            lltv: 0.625e18
        });
    }

    /// @notice Reentry into `updatePriceEarlyAndLiquidate` through a
    ///         malicious `morphoBlue.liquidate()` callback must revert with
    ///         the inline guard's exact message — proving the guard fires
    ///         BEFORE any state mutation on the second call.
    function testNonReentrantBlocksReentry() public {
        MarketParams memory params = _params();
        bytes32 id = keccak256(abi.encode(params));

        vm.prank(owner);
        wrapper.setApprovedMarket(id, true);

        // Fund the attacker so the outer call gets past safeTransferFrom.
        loanToken.mint(address(this), 10e18);
        loanToken.approve(address(wrapper), 10e18);

        evilMorpho.setReentryTarget(address(wrapper), params);

        // The outer call surfaces the inner revert verbatim.
        vm.expectRevert("ChainlinkOEVMorphoWrapper: reentrant call");
        wrapper.updatePriceEarlyAndLiquidate(params, address(0xBEEF), 1, 5e18);
    }
}

/// @notice Callback-enabled loan token: its `transferFrom` fires a hook that
///         reads the wrapper's `cachedRoundId()` / `latestRoundData()` at the
///         instant the loan-token pull runs inside
///         `updatePriceEarlyAndLiquidate`. Models an ERC777/ERC1363-style
///         transfer hook that hands control to the liquidator mid-pull.
contract CallbackLoanToken is MockERC20Decimals {
    ChainlinkOEVMorphoWrapper public wrapper;
    bool public armed;
    bool public captured;
    uint256 public observedCachedRoundId;
    uint80 public observedLatestRoundId;

    constructor() MockERC20Decimals("CallbackLoan", "CBL", 18) {}

    function arm(address _wrapper) external {
        wrapper = ChainlinkOEVMorphoWrapper(_wrapper);
        armed = true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        // Capture only the first pull (liquidator -> wrapper), which is the
        // window HAL-02 is about: if the fresh round were already unlocked
        // here, the liquidator could re-enter Morpho Blue at the fresh price.
        if (armed && !captured && address(wrapper) != address(0)) {
            captured = true;
            observedCachedRoundId = wrapper.cachedRoundId();
            (uint80 rid, , , , ) = wrapper.latestRoundData();
            observedLatestRoundId = rid;
        }
        return super.transferFrom(from, to, amount);
    }
}

/// @notice Benign Morpho Blue mock: `liquidate()` seizes collateral to the
///         caller (the wrapper) so the fee-split path can run to completion,
///         and returns configurable seized/repaid amounts.
contract BenignMorphoBlue {
    MockERC20Decimals public collateralToken;
    uint256 public seizeReturn;
    uint256 public repaidReturn;

    function config(
        address _collateralToken,
        uint256 _seizeReturn,
        uint256 _repaidReturn
    ) external {
        collateralToken = MockERC20Decimals(_collateralToken);
        seizeReturn = _seizeReturn;
        repaidReturn = _repaidReturn;
    }

    function liquidate(
        MarketParams memory,
        address,
        uint256,
        uint256,
        bytes memory
    ) external returns (uint256, uint256) {
        // Send seized collateral to the wrapper so it can split the fee.
        collateralToken.transfer(msg.sender, seizeReturn);
        return (seizeReturn, repaidReturn);
    }
}

/// @notice HAL-02 regression: the loan-token pull in
///         `updatePriceEarlyAndLiquidate` must run BEFORE `cachedRoundId` is
///         advanced to the fresh round, so a callback-enabled loan token that
///         receives control during the pull cannot observe (and therefore
///         cannot exploit via Morpho Blue's native `liquidate()`) a globally
///         unlocked fresh price.
contract ChainlinkOEVMorphoWrapperHAL02UnitTest is Test {
    address internal owner = address(0xA11CE);
    address internal proxyAdmin = address(0xAD317);
    address internal feeRecipient = address(0xFEE);
    address internal chainlinkOracle = address(0xCAFE);
    address internal morphoOracle = address(0xB00B);

    // Round R0 is the pre-liquidation cached (delayed/locked) round; R1 is the
    // fresh round that the function unlocks. They must differ for the test to
    // distinguish the old ordering (observes R1) from the fixed one (R0).
    uint80 internal constant R0 = 1;
    uint80 internal constant R1 = 2;

    MockChainlinkOracle internal priceFeed;
    MockChainlinkOracle internal loanFeed;
    CallbackLoanToken internal loanToken;
    MockERC20Decimals internal collateralToken;
    BenignMorphoBlue internal morpho;

    ChainlinkOEVMorphoWrapper internal wrapper;

    function setUp() public {
        // Wrapper's own collateral price feed, seeded at round R0. cachedRoundId
        // is initialized to latestRound() == R0 in initializeV2.
        priceFeed = new MockChainlinkOracle(1e8, 8);
        priceFeed.set(R0, 1e8, 1, block.timestamp, R0);

        // Per-market Morpho loan (quote) feed.
        loanFeed = new MockChainlinkOracle(1e8, 8);
        loanFeed.set(1, 1e8, 1, block.timestamp, 1);

        loanToken = new CallbackLoanToken();
        collateralToken = new MockERC20Decimals("Coll", "COLL", 18);
        morpho = new BenignMorphoBlue();

        ChainlinkOEVMorphoWrapper impl = new ChainlinkOEVMorphoWrapper();
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            proxyAdmin,
            ""
        );
        wrapper = ChainlinkOEVMorphoWrapper(address(proxy));
        wrapper.initializeV2(
            address(priceFeed),
            owner,
            address(morpho),
            chainlinkOracle,
            feeRecipient,
            500,
            3600,
            10
        );

        // Per-market Morpho oracle: BASE_FEED_1 must equal the wrapper (gate),
        // QUOTE_FEED_1 is the loan aggregator, and both chained-feed slots are
        // zero so the split math passes its defensive checks.
        vm.mockCall(
            morphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.BASE_FEED_1.selector
            ),
            abi.encode(address(wrapper))
        );
        vm.mockCall(
            morphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.QUOTE_FEED_1.selector
            ),
            abi.encode(address(loanFeed))
        );
        vm.mockCall(
            morphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.QUOTE_FEED_2.selector
            ),
            abi.encode(address(0))
        );
        vm.mockCall(
            morphoOracle,
            abi.encodeWithSelector(
                IMorphoChainlinkOracleV2.BASE_FEED_2.selector
            ),
            abi.encode(address(0))
        );
    }

    function _params() internal view returns (MarketParams memory p) {
        p = MarketParams({
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            oracle: morphoOracle,
            irm: address(0),
            lltv: 0.625e18
        });
    }

    /// @notice HAL-02: a callback-enabled loan token whose transfer hook fires
    ///         during the `safeTransferFrom` pull must observe `cachedRoundId`
    ///         (and `latestRoundData`) STILL at the pre-liquidation, locked
    ///         round R0 — NOT the fresh round R1. Fails on the pre-fix ordering
    ///         (pull after the advance) and passes once the pull precedes it.
    function testHAL02LoanTokenPullOccursBeforeFreshRoundUnlock() public {
        MarketParams memory params = _params();
        bytes32 id = keccak256(abi.encode(params));

        vm.prank(owner);
        wrapper.setApprovedMarket(id, true);

        // Advance the underlying feed to the fresh round R1. cachedRoundId is
        // still R0 until updatePriceEarlyAndLiquidate advances it internally.
        priceFeed.set(R1, 1e8, 1, block.timestamp, R1);
        assertEq(wrapper.cachedRoundId(), R0, "precondition: cached == R0");

        uint256 maxRepayAmount = 5e18;
        uint256 seizeReturn = 10e18;
        // No excess (repaid == max) so the refund path is a no-op.
        morpho.config(address(collateralToken), seizeReturn, maxRepayAmount);

        // Fund the liquidation: loan tokens from the caller, collateral in the
        // Morpho mock so it can seize to the wrapper.
        loanToken.mint(address(this), maxRepayAmount);
        loanToken.approve(address(wrapper), maxRepayAmount);
        collateralToken.mint(address(morpho), seizeReturn);

        // Arm the loan token so its transferFrom hook records what the fresh
        // round looks like from an external caller's perspective at pull time.
        loanToken.arm(address(wrapper));

        wrapper.updatePriceEarlyAndLiquidate(
            params,
            address(0xBEEF),
            seizeReturn,
            maxRepayAmount
        );

        assertTrue(loanToken.captured(), "hook never fired during the pull");

        // The crux of HAL-02: at pull time the fresh round is NOT yet unlocked.
        assertEq(
            loanToken.observedCachedRoundId(),
            R0,
            "loan-token pull saw the FRESH round unlocked (HAL-02 regression)"
        );
        assertEq(
            loanToken.observedLatestRoundId(),
            R0,
            "latestRoundData returned the fresh round mid-pull (HAL-02)"
        );

        // Sanity: the unlock is scoped and restored — cachedRoundId is back to
        // R0 after the liquidation completes.
        assertEq(
            wrapper.cachedRoundId(),
            R0,
            "cachedRoundId not restored after liquidation"
        );
    }
}

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

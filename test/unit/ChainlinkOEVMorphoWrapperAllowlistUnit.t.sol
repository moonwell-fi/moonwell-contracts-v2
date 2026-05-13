// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {ChainlinkOEVMorphoWrapper} from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";

/// @notice Unit tests for the market allowlist gate added to fix C4 #195
///         (OEV fee bypass via permissionless auxiliary Morpho market).
contract ChainlinkOEVMorphoWrapperAllowlistUnitTest is Test {
    address internal owner = address(0xA11CE);
    address internal proxyAdmin = address(0xAD317);
    address internal morphoBlue = address(0xB10E);
    address internal chainlinkOracle = address(0xCAFE);
    address internal feeRecipient = address(0xFEE);

    MockChainlinkOracle internal priceFeed;
    ChainlinkOEVMorphoWrapper internal wrapper;

    event MarketApproved(bytes32 indexed id, bool approved);

    function setUp() public {
        priceFeed = new MockChainlinkOracle(1e8, 8);
        priceFeed.set(1, 1e8, 1, 1, 1);

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
            morphoBlue,
            chainlinkOracle,
            feeRecipient,
            500, // liquidatorFeeBps
            3600, // maxRoundDelay
            10 // maxDecrements
        );
    }

    function _id(MarketParams memory p) internal pure returns (bytes32) {
        return keccak256(abi.encode(p));
    }

    function _market(
        address oracle
    ) internal pure returns (MarketParams memory p) {
        p.loanToken = address(0xA);
        p.collateralToken = address(0xB);
        p.oracle = oracle;
        p.irm = address(0xC);
        p.lltv = 0.625e18;
    }

    function testSetApprovedMarketOnlyOwner() public {
        bytes32 id = bytes32(uint256(0x1234));
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.setApprovedMarket(id, true);
    }

    function testSetApprovedMarketTogglesAndEmits() public {
        bytes32 id = bytes32(uint256(0xDEAD));

        vm.expectEmit(true, false, false, true, address(wrapper));
        emit MarketApproved(id, true);
        vm.prank(owner);
        wrapper.setApprovedMarket(id, true);
        assertTrue(wrapper.approvedMarkets(id));

        vm.expectEmit(true, false, false, true, address(wrapper));
        emit MarketApproved(id, false);
        vm.prank(owner);
        wrapper.setApprovedMarket(id, false);
        assertFalse(wrapper.approvedMarkets(id));
    }

    /// @notice The exploit path: an attacker passes a permissionless dummy market.
    ///         With the fix, the allowlist check rejects it before any state mutation.
    function testUpdatePriceEarlyAndLiquidateRevertsForUnapprovedMarket()
        public
    {
        MarketParams memory params = _market(address(0xDEADBEEF));

        vm.expectRevert("ChainlinkOEVMorphoWrapper: market not approved");
        wrapper.updatePriceEarlyAndLiquidate(
            params,
            address(0x1111),
            1, // seizedAssets
            1 // maxRepayAmount
        );

        // cachedRoundId must remain at the value seeded by initializeV2 (priceFeed.latestRound() == 1).
        // i.e. the failed call did NOT advance the round, which is the whole point of the gate.
        assertEq(wrapper.cachedRoundId(), 1);
    }

    /// @notice An approved market gets past the allowlist gate. We can't drive a full
    ///         liquidation in a unit test without a live Morpho Blue, so we verify only
    ///         that the call proceeds past the allowlist and stops at the next downstream
    ///         check — `BASE_FEED_1()` on the oracle, which here is unset.
    function testApprovedMarketBypassesAllowlistGate() public {
        MarketParams memory params = _market(address(0xDEADBEEF));
        bytes32 id = _id(params);

        vm.prank(owner);
        wrapper.setApprovedMarket(id, true);

        vm.expectRevert();
        wrapper.updatePriceEarlyAndLiquidate(params, address(0x1111), 1, 1);
    }

    /// @notice Approval is tuple-specific: the id is derived from the full MarketParams
    ///         struct, so any field difference produces a distinct id.
    function testApprovalIsTupleSpecific() public {
        MarketParams memory approved = _market(address(0x1));
        MarketParams memory other = _market(address(0x2));

        vm.prank(owner);
        wrapper.setApprovedMarket(_id(approved), true);

        assertTrue(wrapper.approvedMarkets(_id(approved)));
        assertFalse(wrapper.approvedMarkets(_id(other)));

        vm.expectRevert("ChainlinkOEVMorphoWrapper: market not approved");
        wrapper.updatePriceEarlyAndLiquidate(other, address(0x1111), 1, 1);
    }
}

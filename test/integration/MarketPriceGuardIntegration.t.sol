// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkOEVWrapper} from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";
import {MarketPriceGuard} from "@test/utils/MarketPriceGuard.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Proposal} from "@proposals/Proposal.sol";

/// @notice a feed whose every call reverts, standing in for a bricked oracle
contract RevertingFeed {
    fallback() external {
        revert("RevertingFeed");
    }
}

/// @notice stands in for a Base MIP declaring cbETH by name only
contract DeclaringProposal {
    uint256 public immutable primaryForkId;

    constructor(uint256 forkId) {
        primaryForkId = forkId;
    }

    function expectedPriceChanges(
        Addresses addresses
    ) external view returns (address[] memory declared) {
        declared = new address[](1);
        declared[0] = addresses.getAddress("MOONWELL_cbETH");
    }
}

/// @notice a MIP artifact compiled before expectedPriceChanges existed
contract StaleProposal {
    uint256 public immutable primaryForkId;

    constructor(uint256 forkId) {
        primaryForkId = forkId;
    }
}

/// @notice Proves MarketPriceGuard catches the MIP-X43 class of mistake on a
/// live Base fork: cbETH re-pointed at the raw cbETH/ETH feed priced at ~1.12
/// instead of ~2,200 USD and CI stayed green.
contract MarketPriceGuardIntegrationTest is Test {
    Addresses public addresses;
    MarketPriceGuard public guard;
    Comptroller public comptroller;
    ChainlinkOracle public oracle;
    uint256 public forkId;
    address public mCbEth;

    function setUp() public {
        forkId = vm.createSelectFork("base");

        addresses = new Addresses();
        guard = new MarketPriceGuard();
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        oracle = ChainlinkOracle(address(comptroller.oracle()));
        mCbEth = addresses.getAddress("MOONWELL_cbETH");

        guard.snapshot(addresses, forkId);
    }

    function _check() internal returns (MarketPriceGuard.Violation[] memory) {
        return guard.check(addresses, forkId, new address[](0));
    }

    function testSnapshotCoversEveryPricedMarket() public view {
        assertTrue(guard.snapshotTaken(forkId), "snapshot not taken");
        MToken[] memory markets = comptroller.getAllMarkets();
        assertGt(markets.length, 0, "no markets on fork");
    }

    function testNoViolationWhenNothingChanges() public {
        assertEq(_check().length, 0, "clean fork reported a violation");
    }

    function testNoViolationAcrossGovernanceWarp() public {
        // PostProposalCheck warps days between snapshot and check
        vm.warp(block.timestamp + 7 days);
        assertEq(_check().length, 0, "warp alone reported a violation");
    }

    function testDetectsMipX43CbEthMispricing() public {
        uint256 before = oracle.getUnderlyingPrice(MToken(mCbEth));

        // exact MIP-X43 misconfiguration: cbETH/ETH ratio feed wired as the USD feed
        // hoisted: a call in argument position would consume the prank
        address ratioFeed = addresses.getAddress("cbETHETH_ORACLE");
        vm.prank(oracle.admin());
        oracle.setFeed("cbETH", ratioFeed);

        MarketPriceGuard.Violation[] memory violations = _check();
        assertEq(violations.length, 1, "expected exactly the cbETH violation");
        assertEq(violations[0].mToken, mCbEth, "wrong market reported");
        assertEq(violations[0].chainId, block.chainid, "wrong chain reported");
        assertEq(
            violations[0].priceBefore,
            before,
            "before price not snapshot"
        );
        // ratio (~1.1e18) is three orders of magnitude under the USD price
        assertLt(
            violations[0].priceAfter * 100,
            violations[0].priceBefore,
            "mispriced cbETH not far enough from USD price"
        );
    }

    function testAllowlistSuppressesDeclaredChange() public {
        // hoisted: a call in argument position would consume the prank
        address ratioFeed = addresses.getAddress("cbETHETH_ORACLE");
        vm.prank(oracle.admin());
        oracle.setFeed("cbETH", ratioFeed);

        address[] memory allowlist = new address[](1);
        allowlist[0] = mCbEth;
        assertEq(
            guard.check(addresses, forkId, allowlist).length,
            0,
            "declared change still reported"
        );
    }

    function testDetectsBrickedFeed() public {
        address bricked = address(new RevertingFeed());
        vm.prank(oracle.admin());
        oracle.setFeed("cbETH", bricked);

        MarketPriceGuard.Violation[] memory violations = _check();
        assertEq(violations.length, 1, "bricked feed not reported");
        assertEq(violations[0].mToken, mCbEth, "wrong market reported");
        assertEq(violations[0].priceAfter, 0, "bricked feed should read 0");
    }

    function testDriftAboveOnePercentIsReported() public {
        uint256 before = oracle.getUnderlyingPrice(MToken(mCbEth));
        address underlying = MErc20(mCbEth).underlying();

        vm.prank(oracle.admin());
        oracle.setDirectPrice(underlying, (before * 102) / 100);

        MarketPriceGuard.Violation[] memory violations = _check();
        assertEq(violations.length, 1, "2% move not reported");
        assertEq(violations[0].mToken, mCbEth, "wrong market reported");
    }

    function testDriftBelowOnePercentIsTolerated() public {
        uint256 before = oracle.getUnderlyingPrice(MToken(mCbEth));
        address underlying = MErc20(mCbEth).underlying();

        vm.prank(oracle.admin());
        oracle.setDirectPrice(underlying, (before * 1005) / 1000);

        assertEq(_check().length, 0, "0.5% move reported");
    }

    function testDescribeNamesFirstViolation() public {
        // hoisted: a call in argument position would consume the prank
        address ratioFeed = addresses.getAddress("cbETHETH_ORACLE");
        vm.prank(oracle.admin());
        oracle.setFeed("cbETH", ratioFeed);

        string memory summary = guard.describe(_check());
        assertTrue(
            bytes(summary).length > 0 &&
                vm.indexOf(summary, "mcbETH") != type(uint256).max,
            "summary does not name the cbETH market"
        );
    }

    /// @notice the MultichainProposalTest shape: snapshot while the OEV wrapper
    /// still serves the delayed round, check after it serves the fresh one
    function testOevRoundSwitchAcrossWarpIsNotReported() public {
        address mCbXrp = addresses.getAddress("MOONWELL_cbXRP");
        ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(
            payable(address(oracle.getFeed("cbXRP")))
        );
        AggregatorV3Interface agg = wrapper.priceFeed();
        (uint80 r0, int256 answer, , , ) = agg.latestRoundData();

        uint256 t = block.timestamp;
        uint80 fresh = r0 + 1;
        // fresh round lands now, 5% above the previous one
        vm.mockCall(
            address(agg),
            abi.encodeWithSelector(agg.latestRoundData.selector),
            abi.encode(fresh, (answer * 105) / 100, t, t, fresh)
        );
        vm.mockCall(
            address(agg),
            abi.encodeWithSelector(agg.getRoundData.selector, r0),
            abi.encode(r0, answer, t - 100, t - 100, r0)
        );

        // within maxRoundDelay: wrapper serves the delayed round
        guard.snapshot(addresses, forkId);
        uint256 before = oracle.getUnderlyingPrice(MToken(mCbXrp));

        vm.warp(t + 1 days);
        uint256 after_ = oracle.getUnderlyingPrice(MToken(mCbXrp));
        assertGt(
            after_ * 100,
            before * 104,
            "fresh round not served after warp"
        );

        assertEq(_check().length, 0, "round switch reported as a price change");
    }

    /// @notice PostProposalCheck resolves declarations with another fork
    /// active (Ethereum last); getAddress(name) must still hit the MIP's chain
    function testDeclarationResolvesOnProposalPrimaryFork() public {
        address proposal = address(new DeclaringProposal(forkId));
        vm.makePersistent(address(guard), address(addresses), proposal);

        // hoisted: a call in argument position would consume the prank
        address ratioFeed = addresses.getAddress("cbETHETH_ORACLE");
        vm.prank(oracle.admin());
        oracle.setFeed("cbETH", ratioFeed);

        uint256 ethFork = vm.createSelectFork("ethereum");
        address[] memory declared = guard.declaredChanges(
            addresses,
            Proposal(proposal)
        );
        assertEq(vm.activeFork(), ethFork, "active fork not restored");
        assertEq(declared.length, 1, "declaration not resolved");
        assertEq(declared[0], mCbEth, "resolved on the wrong chain");

        assertEq(
            guard.check(addresses, forkId, declared).length,
            0,
            "declared change still reported"
        );
    }

    function testStaleArtifactDeclaresNothing() public {
        address proposal = address(new StaleProposal(forkId));
        assertEq(
            guard.declaredChanges(addresses, Proposal(proposal)).length,
            0,
            "stale artifact should fail closed"
        );
    }
}

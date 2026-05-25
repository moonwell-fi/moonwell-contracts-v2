pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV1Moonbeam} from "@protocol/views/MoonwellViewsV1Moonbeam.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

/// @notice Regression test for the Moonbeam-specific views storage layout.
///
/// The Moonbeam MOONWELL_VIEWS_PROXY was initialized in Sep 2023 with the
/// original BaseMoonwellViews state variable order:
///   slot 0 comptroller / slot 1 _tokenSaleDistributor / slot 2 safetyModule
///   slot 3 governanceToken / slot 4 _governanceTokenLP / slot 5 _nativeMarket
///
/// Commit 04c5bc48 (Mar 2024) reordered those vars in BaseMoonwellViews to
///   slot 0 comptroller / slot 1 governanceToken / slot 2 _tokenSaleDistributor
///   slot 3 safetyModule / slot 4 _governanceTokenLP / slot 5 _nativeMarket
///
/// Upgrading the Moonbeam proxy to a post-reorder impl makes safetyModule
/// resolve to the WELL token address — getUserStakingInfo then reverts on
/// "unrecognized function selector" when calling getTotalRewardsBalance on
/// the WELL token. This test forks Moonbeam, upgrades the live proxy to the
/// legacy-layout MoonwellViewsV1Moonbeam, and confirms both views resolve
/// correctly.
contract MoonwellViewsV1MoonbeamLiveProxyTest is Test, PostProposalCheck {
    /// @notice Staker with both stkWELL balance and pending rewards on
    /// Moonbeam at recent blocks.
    address public constant STAKER = 0x1EDDc668902A812De0072c61d5e0cd80A8e2E732;

    function setUp() public override {
        super.setUp();
        // 0 == Moonbeam fork in PostProposalCheck.setUp ordering.
        vm.selectFork(0);
    }

    function testUpgradeFixesGetUserStakingInfo() public {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            addresses.getAddress("MOONWELL_VIEWS_PROXY")
        );
        ProxyAdmin proxyAdmin = ProxyAdmin(
            addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN")
        );

        MoonwellViewsV1Moonbeam newImpl = new MoonwellViewsV1Moonbeam();

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgrade(proxy, address(newImpl));

        MoonwellViewsV1Moonbeam views = MoonwellViewsV1Moonbeam(address(proxy));

        // Sanity: safetyModule now resolves to the real stkWELL proxy, not
        // the WELL token.
        assertEq(
            address(views.safetyModule()),
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            "safetyModule must point at stkWELL after upgrade"
        );
        assertEq(
            address(views.governanceToken()),
            addresses.getAddress("WELL"),
            "governanceToken must point at WELL after upgrade"
        );

        // Pre-fix, this reverted with "unrecognized function selector
        // 0x8dbefee2 for contract 0x511a…11E3 [WELL]". With the legacy layout
        // the call lands on stkWELL and returns the staker's pending rewards.
        MoonwellViewsV1Moonbeam.UserStakingInfo memory info = views
            .getUserStakingInfo(STAKER);
        assertGt(
            info.totalStaked,
            0,
            "STAKER must have a non-zero stkWELL balance"
        );

        // Timestamp-keyed getPriorVotes returns the staker's snapshot balance.
        MoonwellViewsV1Moonbeam.Votes memory votes = views
            .getUserStakingVotingPower(STAKER);
        assertEq(
            votes.delegatedVotingPower,
            info.totalStaked,
            "delegatedVotingPower should equal totalStaked for an auto-delegated stkWELL holder"
        );
    }
}

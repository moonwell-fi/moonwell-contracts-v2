pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MoonwellViewsV1Moonbeam} from "@protocol/views/MoonwellViewsV1Moonbeam.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

/// @notice Regression test for the Moonbeam-specific views storage
/// layout AND the post-mip-x58 voting-source updates.
///
/// Layout: the Moonbeam MOONWELL_VIEWS_PROXY was initialized in Sep
/// 2023 with the original BaseMoonwellViews state variable order:
///   slot 0 comptroller / slot 1 _tokenSaleDistributor / slot 2 safetyModule
///   slot 3 governanceToken / slot 4 _governanceTokenLP / slot 5 _nativeMarket
/// Commit 04c5bc48 (Mar 2024) reordered those vars, so upgrading to the
/// current MoonwellViewsV1 would scramble safetyModule / governanceToken.
/// MoonwellViewsV1Moonbeam preserves the legacy slot order.
///
/// Voting sources: mip-x58 (id 168) registered only stkWELL on every
/// VotingPowerAggregator. xWELL is the always-on custom source. WELL
/// and the TokenSaleDistributor are no longer counted, so the
/// MoonwellViewsV1Moonbeam impl re-reads `tokenVotes` from xWELL and
/// zeros `claimsVotes.delegatedVotingPower`.
contract MoonwellViewsV1MoonbeamLiveProxyTest is Test, PostProposalCheck {
    /// @notice Staker with stkWELL balance and pending rewards on
    /// Moonbeam at recent blocks.
    address public constant STAKER = 0x1EDDc668902A812De0072c61d5e0cd80A8e2E732;

    /// @notice Holder with native WELL on Moonbeam but no xWELL and
    /// no stkWELL. Pre-fix the views reported their WELL balance as
    /// `tokenVotes`; post-fix all three voting-power buckets must be
    /// zero because the on-chain VotingPowerAggregator (per mip-x58)
    /// only sums xWELL + stkWELL.
    address public constant WELL_ONLY_HOLDER =
        0x45db397E443721D77480ADbFae4753D003D28F1D;

    function setUp() public override {
        super.setUp();
        // 0 == Moonbeam fork in PostProposalCheck.setUp ordering.
        vm.selectFork(0);
    }

    function testUpgradeFixesGetUserStakingInfo() public {
        MoonwellViewsV1Moonbeam views = _upgradeWithInitV2();

        // Sanity: storage slots still resolve correctly after the
        // upgrade (legacy layout preserved).
        assertEq(
            address(views.safetyModule()),
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            "safetyModule must point at stkWELL after upgrade"
        );
        assertEq(
            address(views.governanceToken()),
            addresses.getAddress("WELL"),
            "governanceToken slot still holds the legacy WELL address"
        );
        assertEq(
            address(views.xWellToken()),
            addresses.getAddress("xWELL_PROXY"),
            "initializeV2 must have set xWellToken to xWELL_PROXY"
        );

        // Pre-fix this reverted with "unrecognized function selector
        // 0x8dbefee2 for contract 0x511a…11E3 [WELL]". With the legacy
        // layout the call lands on stkWELL.
        MoonwellViewsV1Moonbeam.UserStakingInfo memory info = views
            .getUserStakingInfo(STAKER);
        assertGt(
            info.totalStaked,
            0,
            "STAKER must have a non-zero stkWELL balance"
        );

        // Timestamp-keyed snapshot read returns the staker's balance.
        MoonwellViewsV1Moonbeam.Votes memory votes = views
            .getUserStakingVotingPower(STAKER);
        assertEq(
            votes.delegatedVotingPower,
            info.totalStaked,
            "delegatedVotingPower should equal totalStaked for an auto-delegated stkWELL holder"
        );
    }

    /// @notice Regression: post-mip-x58, `tokenVotes` reads xWELL
    /// (not WELL — WELL is no longer a snapshot source on the
    /// VotingPowerAggregator).
    function testTokensVotingPowerReadsXWell() public {
        MoonwellViewsV1Moonbeam views = _upgradeWithInitV2();

        xWELL xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        MoonwellViewsV1Moonbeam.Votes memory tv = views
            .getUserTokensVotingPower(STAKER);

        assertEq(
            tv.votingPower,
            xwell.balanceOf(STAKER),
            "tokenVotes.votingPower must track xWELL.balanceOf"
        );
        assertEq(
            tv.delegatedVotingPower,
            xwell.getVotes(STAKER),
            "tokenVotes.delegatedVotingPower must track xWELL.getVotes"
        );
        assertEq(
            tv.delegates,
            xwell.delegates(STAKER),
            "tokenVotes.delegates must track xWELL.delegates"
        );
    }

    /// @notice Regression: post-mip-x58 the TokenSaleDistributor is no
    /// longer a snapshot source, so `claimsVotes.delegatedVotingPower`
    /// must be zero even if the user has unclaimed vested tokens.
    function testClaimsVotingPowerDelegatedIsZero() public {
        MoonwellViewsV1Moonbeam views = _upgradeWithInitV2();
        MoonwellViewsV1Moonbeam.Votes memory cv = views
            .getUserClaimsVotingPower(STAKER);
        assertEq(
            cv.delegatedVotingPower,
            0,
            "claimsVotes.delegatedVotingPower must be 0 post mip-x58"
        );
    }

    /// @notice Regression for the bug Carlos hit: a Moonbeam holder
    /// with only native WELL — no xWELL, no stkWELL — used to see
    /// their WELL balance reported as `tokenVotes`, even though WELL
    /// is no longer a snapshot source on the VotingPowerAggregator
    /// (per mip-x58). After the fix, every voting-power bucket must
    /// be zero for this user. WELL balance itself is left untouched
    /// (it's still a real ERC20 — just no longer counts toward votes).
    function testWellOnlyHolderHasZeroVotingPower() public {
        MoonwellViewsV1Moonbeam views = _upgradeWithInitV2();

        MoonwellViewsV1Moonbeam.UserVotes memory uv = views.getUserVotingPower(
            WELL_ONLY_HOLDER
        );

        // tokenVotes now reads xWELL — holder has none.
        assertEq(
            uv.tokenVotes.delegatedVotingPower,
            0,
            "tokenVotes.delegatedVotingPower must be 0 (no xWELL)"
        );
        assertEq(
            uv.tokenVotes.votingPower,
            0,
            "tokenVotes.votingPower must be 0 (no xWELL balance)"
        );

        // stakingVotes reads stkWELL — holder is not staking.
        assertEq(
            uv.stakingVotes.delegatedVotingPower,
            0,
            "stakingVotes.delegatedVotingPower must be 0 (not staking)"
        );
        assertEq(
            uv.stakingVotes.votingPower,
            0,
            "stakingVotes.votingPower must be 0 (no stkWELL balance)"
        );

        // claimsVotes.delegatedVotingPower is zeroed post mip-x58
        // even if the user has unclaimed vested tokens. votingPower
        // (the unclaimed-balance display) may be non-zero for some
        // holders but is irrelevant to the "can they vote" question.
        assertEq(
            uv.claimsVotes.delegatedVotingPower,
            0,
            "claimsVotes.delegatedVotingPower must be 0 post mip-x58"
        );
    }

    /// @notice initializeV2 must not be callable twice — guards against
    /// a future upgrade accidentally re-wiring xWellToken.
    function testInitializeV2NotCallableTwice() public {
        MoonwellViewsV1Moonbeam views = _upgradeWithInitV2();
        // Hoist the arg out so `vm.expectRevert` matches the
        // initializeV2 call, not the addresses.getAddress one.
        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        vm.expectRevert("Initializable: contract is already initialized");
        views.initializeV2(xWellProxy);
    }

    /// @dev Upgrade the live Moonbeam views proxy to a fresh
    ///      MoonwellViewsV1Moonbeam impl AND atomically run
    ///      initializeV2(xWELL_PROXY) — same shape the production
    ///      script uses.
    function _upgradeWithInitV2()
        internal
        returns (MoonwellViewsV1Moonbeam views)
    {
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            addresses.getAddress("MOONWELL_VIEWS_PROXY")
        );
        ProxyAdmin proxyAdmin = ProxyAdmin(
            addresses.getAddress("MOONWELL_VIEWS_PROXY_ADMIN")
        );
        MoonwellViewsV1Moonbeam newImpl = new MoonwellViewsV1Moonbeam();
        bytes memory initdata = abi.encodeCall(
            MoonwellViewsV1Moonbeam.initializeV2,
            (addresses.getAddress("xWELL_PROXY"))
        );
        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgradeAndCall(proxy, address(newImpl), initdata);
        views = MoonwellViewsV1Moonbeam(address(proxy));
    }
}

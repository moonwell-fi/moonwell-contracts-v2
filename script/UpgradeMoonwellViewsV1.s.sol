// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1Moonbeam} from "@protocol/views/MoonwellViewsV1Moonbeam.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
Upgrades the Moonbeam views implementation behind MOONWELL_VIEWS_PROXY
and atomically calls initializeV2 to wire xWELL.

Fixes two display bugs at once:
 - getUserStakingVotingPower previously queried stkWELL.getPriorVotes
   with block.number while stkWELL snapshots (ERC20WithSnapshot) are
   keyed by block.timestamp — so delegatedVotingPower always returned 0.
 - getUserTokensVotingPower previously read the legacy `governanceToken`
   slot (WELL). Post mip-x58 the VotingPowerAggregator only sums
   xWELL + stkWELL — WELL no longer counts as a voting source. Wire
   xWELL via initializeV2 and let the override expose xWELL votes.

Deploys MoonwellViewsV1Moonbeam (not MoonwellViewsV1) because the
Moonbeam proxy was initialized against the original Sep-2023 storage
layout. A later refactor in commit 04c5bc48 reordered state variables
in BaseMoonwellViews, which would shift `safetyModule` to the slot
holding the WELL token if the post-reorder implementation were deployed
against this proxy. The Moonbeam-specific base preserves the legacy
slot order.

Must be broadcast by the MOONWELL_VIEWS_PROXY_ADMIN owner
(MOONWELL_DEPLOYER).

to run:
forge script script/UpgradeMoonwellViewsV1.s.sol:UpgradeMoonwellViewsV1 -vvvv --rpc-url moonbeam --broadcast
*/

contract UpgradeMoonwellViewsV1 is Script {
    Addresses public addresses;

    /// @notice Moonbeam holder with stkWELL balance > 0. Used as the
    ///         no-regression canary: their stakingVotes must be
    ///         identical before and after the upgrade.
    /// @dev    Note that the bug Carlos originally reported (stkWELL
    ///         snapshot keyed by block.number) is ALREADY fixed in the
    ///         live impl on Moonbeam at the time this script was
    ///         written — verified by reading the ERC1967 slot and
    ///         observing the live impl returns 185k stkWELL voting
    ///         power for this address. So the script's stkWELL
    ///         pre/post comparison is a no-regression check, not a
    ///         bug-fix-applied check.
    address public constant SAMPLE_STAKER =
        0x1EDDc668902A812De0072c61d5e0cd80A8e2E732;

    /// @notice Moonbeam holder with native WELL balance > 0 and no
    ///         xWELL. Used as the WELL-to-xWELL transition canary:
    ///         pre-upgrade `tokenVotes.votingPower` reflects WELL
    ///         (was the bug), post-upgrade it reflects xWELL (= 0).
    /// @dev    This is the address Carlos used to surface the
    ///         "tokenVotes returns my WELL" complaint.
    address public constant WELL_ONLY_HOLDER =
        0x45db397E443721D77480ADbFae4753D003D28F1D;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        address stkGovToken = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address well = addresses.getAddress("WELL");
        address proxyAdminAddr = addresses.getAddress(
            "MOONWELL_VIEWS_PROXY_ADMIN"
        );
        address proxyAddr = addresses.getAddress("MOONWELL_VIEWS_PROXY");

        MoonwellViewsV1Moonbeam viewsProxy = MoonwellViewsV1Moonbeam(proxyAddr);

        // ------------------------------------------------------------------
        // PRE-UPGRADE SNAPSHOT
        // Record the values we want to be preserved (storage layout +
        // stkWELL voting) and the values we expect to change (tokenVotes
        // source, claims delegated power). Compared post-upgrade below.
        // ------------------------------------------------------------------
        address preComptroller = address(viewsProxy.comptroller());
        address preSafetyModule = address(viewsProxy.safetyModule());
        address preGovernanceToken = address(viewsProxy.governanceToken());

        MoonwellViewsV1Moonbeam.UserVotes memory preStakerVotes = viewsProxy
            .getUserVotingPower(SAMPLE_STAKER);
        MoonwellViewsV1Moonbeam.UserVotes memory preWellHolderVotes = viewsProxy
            .getUserVotingPower(WELL_ONLY_HOLDER);

        // Preconditions — fail loudly if the chosen sample addresses no
        // longer have the state we depend on. Update the constants and
        // re-run if these fail.
        require(
            preStakerVotes.stakingVotes.votingPower > 0,
            "SAMPLE_STAKER has no stkWELL balance"
        );
        require(
            preWellHolderVotes.tokenVotes.votingPower > 0,
            "WELL_ONLY_HOLDER has no WELL balance"
        );

        // ------------------------------------------------------------------
        // BROADCAST
        // ------------------------------------------------------------------
        vm.startBroadcast();

        MoonwellViewsV1Moonbeam viewsImpl = new MoonwellViewsV1Moonbeam();

        bytes memory initdata = abi.encodeCall(
            MoonwellViewsV1Moonbeam.initializeV2,
            (xWellProxy)
        );

        ProxyAdmin(proxyAdminAddr).upgradeAndCall(
            ITransparentUpgradeableProxy(proxyAddr),
            address(viewsImpl),
            initdata
        );

        vm.stopBroadcast();

        // ------------------------------------------------------------------
        // POST-UPGRADE VALIDATION
        // ------------------------------------------------------------------

        // 1. Layout invariant: every public-getter slot resolves to the same
        //    address it did pre-upgrade, AND matches the registry's expected
        //    value (defends against both layout drift and registry drift).
        require(
            address(viewsProxy.comptroller()) == preComptroller,
            "comptroller slot drifted"
        );
        require(
            address(viewsProxy.safetyModule()) == preSafetyModule &&
                preSafetyModule == stkGovToken,
            "safetyModule slot drifted"
        );
        require(
            address(viewsProxy.governanceToken()) == preGovernanceToken &&
                preGovernanceToken == well,
            "governanceToken slot drifted"
        );

        // 2. New state: initializeV2 wired xWELL.
        require(
            address(viewsProxy.xWellToken()) == xWellProxy,
            "xWellToken not wired by initializeV2"
        );

        // 3a. No-regression check on SAMPLE_STAKER. The stkWELL timestamp
        //     fix is already live, so stakingVotes must NOT change across
        //     this upgrade. tokenVotes for SAMPLE_STAKER is zero pre and
        //     post (no WELL, no xWELL) but we still confirm the override
        //     is reading xWELL by checking equality against xWELL.balanceOf.
        MoonwellViewsV1Moonbeam.UserVotes memory postStakerVotes = viewsProxy
            .getUserVotingPower(SAMPLE_STAKER);

        require(
            postStakerVotes.stakingVotes.votingPower ==
                preStakerVotes.stakingVotes.votingPower,
            "regression: stkWELL balance changed across upgrade"
        );
        require(
            postStakerVotes.stakingVotes.delegatedVotingPower ==
                preStakerVotes.stakingVotes.delegatedVotingPower,
            "regression: stkWELL delegated voting power changed across upgrade"
        );
        require(
            postStakerVotes.stakingVotes.delegatedVotingPower ==
                postStakerVotes.stakingVotes.votingPower,
            "stkWELL delegated should match balance for an auto-delegated holder"
        );
        require(
            postStakerVotes.tokenVotes.votingPower ==
                xWELL(xWellProxy).balanceOf(SAMPLE_STAKER),
            "tokenVotes override not reading xWELL balance for SAMPLE_STAKER"
        );

        // 3b. The fix-applied check on WELL_ONLY_HOLDER. Pre-upgrade their
        //     tokenVotes reflects WELL (the bug Carlos surfaced). Post-
        //     upgrade it must reflect xWELL — which they have zero of, so
        //     all voting power buckets should be zero. This is the
        //     "the user with no real voting power finally shows 0" check.
        MoonwellViewsV1Moonbeam.UserVotes
            memory postWellHolderVotes = viewsProxy.getUserVotingPower(
                WELL_ONLY_HOLDER
            );

        // Sanity that the precondition held — pre tokenVotes was non-zero
        // (WELL.balanceOf) and so was tokenVotes.delegatedVotingPower if
        // they were self-delegating WELL. Post must drop to xWELL.
        require(
            postWellHolderVotes.tokenVotes.votingPower !=
                preWellHolderVotes.tokenVotes.votingPower,
            "fix not applied: tokenVotes.votingPower unchanged for WELL_ONLY_HOLDER"
        );
        require(
            postWellHolderVotes.tokenVotes.votingPower ==
                xWELL(xWellProxy).balanceOf(WELL_ONLY_HOLDER),
            "tokenVotes override not reading xWELL balance for WELL_ONLY_HOLDER"
        );
        require(
            postWellHolderVotes.tokenVotes.delegatedVotingPower ==
                xWELL(xWellProxy).getVotes(WELL_ONLY_HOLDER),
            "tokenVotes delegatedVotingPower not reading xWELL.getVotes for WELL_ONLY_HOLDER"
        );
        require(
            postWellHolderVotes.claimsVotes.delegatedVotingPower == 0,
            "claimsVotes override not zeroing delegated power"
        );

        console.log(
            "new MoonwellViewsV1Moonbeam implementation:",
            address(viewsImpl)
        );
    }
}

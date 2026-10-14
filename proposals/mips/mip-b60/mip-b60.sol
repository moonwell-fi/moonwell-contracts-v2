//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposalV2, ActionType} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {BASE_FORK_ID, ChainIds} from "@utils/ChainIds.sol";

/// @notice minimal view surface of the Base stkWELL (StakedWell behind
/// STK_GOVTOKEN_PROXY). Declared locally because src/stkWell is pinned to
/// solidity 0.6.12 and cannot be imported into a 0.8.19 proposal.
interface IStakedWellCooldown {
    function COOLDOWN_SECONDS() external view returns (uint256);

    function UNSTAKE_WINDOW() external view returns (uint256);

    function EMISSION_MANAGER() external view returns (address);

    function STAKED_TOKEN() external view returns (address);

    function totalSupply() external view returns (uint256);
}

/// @notice minimal view surface shared by the two Base contracts that carry a
/// pause guardian: the Comptroller (behind UNITROLLER) and the
/// MultiRewardDistributor (MRD_PROXY).
interface IPauseGuardianHolder {
    function pauseGuardian() external view returns (address);
}

/// @notice Comptroller admin check, used to prove both setters are callable by
/// the Temporal Governor.
interface IComptrollerAdmin {
    function admin() external view returns (address);
}

/// @title MIP-B60: Temporary Base Safety Module cooldown extension + pause
///        guardian migration
/// @notice Three Base actions:
///
///         1. raise the Base stkWELL unstaking cooldown from 7 days to 30
///            days. The 2-day unstake window is left unchanged.
///         2. point the Comptroller's pause guardian at the new security
///            council multisig (PAUSE_GUARDIAN).
///         3. point the MultiRewardDistributor's pause guardian at the same
///            multisig.
///
///         Base carries the pause guardian role on BOTH the Comptroller and
///         the MRD, and both currently sit on the deprecated multisig
///         (PAUSE_GUARDIAN_DEPRECATED). Ethereum already has both on
///         PAUSE_GUARDIAN, so moving only one would leave Base out of sync
///         and leave reward-distribution pause power with the old signer set.
///
///         `setCoolDownSeconds` is gated by `onlyEmissionsManager`, and the
///         EMISSION_MANAGER of the Base stkWELL is the Base Temporal Governor
///         (verified in build()), which is what executes this proposal's Base
///         action — so the call is authorized.
///
///         Direct precedent: MIP-X62 used the same setter on the Moonbeam
///         stkWELL (7 days -> 0) as part of the Moonbeam wind-down.
///
/// @dev ENGINEERING NOTE (not a staker-facing claim): the change is
///      RETROACTIVE. StakedToken.redeem re-reads the current COOLDOWN_SECONDS
///      rather than the value in force when the staker activated their
///      cooldown (src/stkWell/StakedToken.sol:149-156), so at execution every
///      in-flight cooldown is measured against the new 30 days — including
///      stakers already inside their 2-day withdrawal window, who are pushed
///      back out until day 30. Grandfathering would require a new stkWELL
///      implementation storing a per-user cooldown length; it is out of scope
///      for a parameter-only proposal.
///
///      getNextCooldownTimestamp does `block.timestamp - COOLDOWN_SECONDS -
///      UNSTAKE_WINDOW` under SafeMath; 30 days + 2 days is far below the
///      current block timestamp, so there is no underflow risk.
///
/// how to generate calldata / run a standalone simulation against forks:
/*
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/
/// forge script proposals/mips/mip-b60/mip-b60.sol:mipb60 --ffi -vvv
contract mipb60 is HybridProposalV2 {
    using ChainIds for uint256;

    string public constant override name = "MIP-B60";

    /// @notice live Base stkWELL cooldown this proposal replaces; asserted in
    /// build() so silent drift between authoring and execution fails the
    /// simulation loudly instead of quietly overwriting an unexpected value.
    uint256 public constant CURRENT_COOLDOWN_SECONDS = 7 days;

    /// @notice the temporary cooldown this proposal installs (2,592,000s)
    uint256 public constant NEW_COOLDOWN_SECONDS = 30 days;

    /// @notice the unstake window, which this proposal must NOT change
    uint256 public constant UNSTAKE_WINDOW_SECONDS = 2 days;

    /// @notice registry key of the deprecated multisig currently holding the
    /// pause guardian role on both Base contracts; asserted in build() so the
    /// proposal fails loudly if the role moved between authoring and execution
    string public constant CURRENT_PAUSE_GUARDIAN_KEY =
        "PAUSE_GUARDIAN_DEPRECATED";

    /// @notice registry key of the new security council multisig taking the
    /// role (0x5B710010586C1b728B047c3E42473c700eeA4026, already the pause
    /// guardian of both equivalent contracts on Ethereum)
    string public constant NEW_PAUSE_GUARDIAN_KEY = "PAUSE_GUARDIAN";

    /// ---------------------------------------------------------------------
    /// pre-execution snapshots captured in afterDeploy() (runs before build()
    /// and simulate()), asserted in validate() so an accidental storage reset
    /// of an untouched field surfaces as a strict-equality failure.
    /// ---------------------------------------------------------------------

    /// @notice stkWELL total supply before execution — must be unchanged
    /// (proves the proposal neither slashes nor mints staker balances)
    uint256 internal preTotalSupply;

    /// @notice WELL held by the Safety Module before execution — must be
    /// unchanged (proves no staked WELL is transferred out)
    uint256 internal preStakedTokenBalance;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b60/b60.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    /// @notice mirrors Proposal.run() minus the top-level broadcast wrapper,
    /// following mip-x64: this proposal deploys nothing, and
    /// afterDeploy()/build()/validate() switch forks, which does not compose
    /// with an active vm.startBroadcast(). Keeps the descriptionUri injection
    /// so DO_PRINT calldata carries the pinned IPFS URI from mips.json.
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        IStakedWellCooldown stkWell = IStakedWellCooldown(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        preTotalSupply = stkWell.totalSupply();
        preStakedTokenBalance = IERC20(stkWell.STAKED_TOKEN()).balanceOf(
            address(stkWell)
        );

        assertGt(
            preTotalSupply,
            0,
            "MIP-B60: stkWELL total supply snapshot is zero (afterDeploy ran against the wrong fork?)"
        );

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        vm.selectFork(BASE_FORK_ID);

        address stkWell = addresses.getAddress("STK_GOVTOKEN_PROXY");

        // setCoolDownSeconds is onlyEmissionsManager; the Base Temporal
        // Governor executes this action, so it must be the emissions manager.
        assertEq(
            IStakedWellCooldown(stkWell).EMISSION_MANAGER(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "MIP-B60: stkWELL emission manager must be the Base Temporal Governor"
        );

        assertEq(
            IStakedWellCooldown(stkWell).COOLDOWN_SECONDS(),
            CURRENT_COOLDOWN_SECONDS,
            "MIP-B60: stkWELL cooldown drifted from the expected 7 days"
        );

        assertEq(
            IStakedWellCooldown(stkWell).UNSTAKE_WINDOW(),
            UNSTAKE_WINDOW_SECONDS,
            "MIP-B60: stkWELL unstake window drifted from the expected 2 days"
        );

        _pushAction(
            stkWell,
            abi.encodeWithSignature(
                "setCoolDownSeconds(uint256)",
                NEW_COOLDOWN_SECONDS
            ),
            "Temporarily set the Base stkWELL unstaking cooldown to 30 days (from 7 days)",
            ActionType.Base
        );

        // ---------------- pause guardian migration ----------------

        address unitroller = addresses.getAddress("UNITROLLER");
        address mrd = addresses.getAddress("MRD_PROXY");
        address newGuardian = addresses.getAddress(NEW_PAUSE_GUARDIAN_KEY);
        address oldGuardian = addresses.getAddress(CURRENT_PAUSE_GUARDIAN_KEY);

        // Comptroller._setPauseGuardian is admin-gated, and the MRD setter is
        // onlyPauseGuardianOrAdmin where MRD's admin is comptroller.admin().
        // Both therefore hinge on the Comptroller admin being the executor.
        assertEq(
            IComptrollerAdmin(unitroller).admin(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "MIP-B60: Comptroller admin must be the Base Temporal Governor"
        );

        assertEq(
            IPauseGuardianHolder(unitroller).pauseGuardian(),
            oldGuardian,
            "MIP-B60: Comptroller pause guardian is not the deprecated multisig"
        );

        assertEq(
            IPauseGuardianHolder(mrd).pauseGuardian(),
            oldGuardian,
            "MIP-B60: MRD pause guardian is not the deprecated multisig"
        );

        assertTrue(
            newGuardian != oldGuardian,
            "MIP-B60: new and old pause guardian resolve to the same address"
        );

        _pushAction(
            unitroller,
            abi.encodeWithSignature("_setPauseGuardian(address)", newGuardian),
            "Set the Comptroller pause guardian to the new security council multisig",
            ActionType.Base
        );

        _pushAction(
            mrd,
            abi.encodeWithSignature("_setPauseGuardian(address)", newGuardian),
            "Set the MultiRewardDistributor pause guardian to the new security council multisig",
            ActionType.Base
        );

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        IStakedWellCooldown stkWell = IStakedWellCooldown(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        assertEq(
            stkWell.COOLDOWN_SECONDS(),
            NEW_COOLDOWN_SECONDS,
            "MIP-B60: stkWELL cooldown must be 30 days after execution"
        );

        assertEq(
            stkWell.UNSTAKE_WINDOW(),
            UNSTAKE_WINDOW_SECONDS,
            "MIP-B60: stkWELL unstake window must be unchanged at 2 days"
        );

        // The proposal explicitly does not slash, sell or transfer staked
        // WELL — pin both sides of that claim against the afterDeploy
        // snapshots.
        assertEq(
            stkWell.totalSupply(),
            preTotalSupply,
            "MIP-B60: stkWELL total supply changed"
        );

        assertEq(
            IERC20(stkWell.STAKED_TOKEN()).balanceOf(address(stkWell)),
            preStakedTokenBalance,
            "MIP-B60: WELL held by the Safety Module changed"
        );

        // Comptroller._setPauseGuardian SILENTLY returns an error code instead
        // of reverting when the caller is not admin, so the only proof the
        // action landed is reading the resulting storage. The MRD setter does
        // revert, but is asserted the same way for symmetry.
        address newGuardian = addresses.getAddress(NEW_PAUSE_GUARDIAN_KEY);

        assertEq(
            IPauseGuardianHolder(addresses.getAddress("UNITROLLER"))
                .pauseGuardian(),
            newGuardian,
            "MIP-B60: Comptroller pause guardian was not updated"
        );

        assertEq(
            IPauseGuardianHolder(addresses.getAddress("MRD_PROXY"))
                .pauseGuardian(),
            newGuardian,
            "MIP-B60: MRD pause guardian was not updated"
        );

        vm.selectFork(primaryForkId());
    }
}

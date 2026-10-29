// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import "./MErc20.sol";

/**
 * @title Moonwell's MErc20Delegate Contract
 * @notice MTokens which wrap an EIP-20 underlying and are delegated to
 * @author Moonwell
 */
contract MErc20Delegate is MErc20, MDelegateInterface {
    /**
     * @notice Internally tracked balance of underlying held by this market
     * @dev Declared here, after MDelegationStorage.implementation, so it
     *      occupies the next free delegator slot (20) without shifting any
     *      existing storage. Updated only by doTransferIn / doTransferOut,
     *      synced to the real balance in _becomeImplementation and lowered by
     *      _syncCashDown. Cash is min(internalCash, underlying balance):
     *      - direct transfers ("donations") above internalCash do not move
     *        the exchange rate or count toward supply caps;
     *      - a loss outside the market (issuer seizure or burn, or a token
     *        that takes more than `amount` on transfer out) is priced at
     *        once and shared pro rata, and redeem / borrow cash checks fail
     *        cleanly against the real balance instead of reverting inside
     *        the token transfer;
     *      - if lost tokens come back, cash recovers up to internalCash with
     *        no governance action, so any tokens sent while the balance is
     *        below internalCash raise the exchange rate up to internalCash.
     */
    uint256 public internalCash;

    /// @notice Emitted when internalCash is synced to the underlying balance
    event CashSynced(uint256 oldInternalCash, uint256 newInternalCash);

    /// @notice Emitted when underlying in excess of internalCash is swept to admin
    event ExcessCashSwept(address indexed recipient, uint256 amount);

    /**
     * @notice Construct an empty delegate
     */
    constructor() {}

    /**
     * @notice Called by the delegator on a delegate to initialize it for duty
     * @dev Always syncs internalCash to the underlying balance, so, like
     *      _syncCashDown, it makes any unsynced loss permanent: schedule
     *      upgrades only once a loss is known to be permanent. Tokens above
     *      internalCash are swept to admin by the outgoing implementation's
     *      _resignImplementation only when _setImplementation is called with
     *      allowResign = true; with allowResign = false they are absorbed
     *      into the exchange rate here and can no longer be swept.
     *      Never sweep here: on the first migration from a balance-based
     *      implementation internalCash is unset and the whole balance would
     *      look like excess. Interest is accrued first at the current cash,
     *      except while internalCash is zero (first migration, new market,
     *      fully borrowed market), where accruing would price utilization at
     *      100%; the next interaction accrues at the synced cash instead.
     *      A rollback to a balance-based implementation (e.g. the archived
     *      *_IMPLEMENTATION_DEPRECATED_V1) never writes or clears this slot,
     *      so it stays stale and non-zero. Any re-upgrade from such an
     *      implementation must call accrueInterest() on the market in the same
     *      transaction before _setImplementation, so the accrual here has no
     *      elapsed period to price at a stale internalCash (getCashPrior caps
     *      a stale value above the balance, but not one below it).
     * @param data The encoded bytes data for any initialization
     */
    function _becomeImplementation(bytes memory data) public virtual override {
        // Shh -- currently unused
        data;

        require(
            msg.sender == admin,
            "only the admin may call _becomeImplementation"
        );

        uint256 oldInternalCash = internalCash;
        if (oldInternalCash != 0) {
            accrueInterest();
        }

        internalCash = EIP20Interface(underlying).balanceOf(address(this));

        emit CashSynced(oldInternalCash, internalCash);
    }

    /**
     * @notice Called by the delegator on a delegate to forfeit its responsibility
     * @dev Sweeps any excess to admin; never writes internalCash
     */
    function _resignImplementation() public virtual override {
        require(
            msg.sender == admin,
            "only the admin may call _resignImplementation"
        );

        _sweepExcess();
    }

    /**
     * @notice Send underlying held above internalCash (donations) to admin
     * @dev Only the untracked excess can be swept, so this can never reduce
     *      the cash backing suppliers, borrows or reserves.
     */
    function _sweepExcessCash() external {
        require(msg.sender == admin, "only the admin may sweep excess cash");

        _sweepExcess();
    }

    /// @dev Sends balance above internalCash to admin as underlying (bypasses
    ///      _transferUnderlyingOut so mWETH sweeps WETH, not ETH)
    function _sweepExcess() internal {
        uint256 balance = EIP20Interface(underlying).balanceOf(address(this));
        uint256 excess = balance > internalCash ? balance - internalCash : 0;

        if (excess != 0) {
            MErc20.doTransferOut(payable(admin), excess);

            emit ExcessCashSwept(admin, excess);
        }
    }

    /**
     * @notice Lower internalCash to the underlying balance after a loss
     *         outside the market (e.g. issuer seizure); never raises it
     * @dev The loss is already priced through getCashPrior; this only makes
     *      it permanent, so tokens returned afterwards are excess (sweepable)
     *      instead of restoring cash. Call it only once a loss is known to be
     *      permanent. A loss that wipes all or nearly all supplier equity
     *      (reserves >= cash + borrows, or utilization pushing the borrow
     *      rate above the max) freezes the market; with borrows outstanding
     *      accrueInterest, and so this function, reverts. Unsynced, the
     *      market recovers by itself once the tokens return; synced, it
     *      stays frozen. Recovery after the tokens return: with no borrows
     *      outstanding, admin calls _becomeImplementation directly (Base WETH:
     *      MWethOwnerWrapper._setImplementation(sameImpl, false, "")); with
     *      borrows outstanding, switch with allowResign = false to a
     *      balance-based implementation (MTOKEN_IMPLEMENTATION_DEPRECATED_V1 /
     *      MWETH_IMPLEMENTATION_DEPRECATED_V1), accrue, and switch back in
     *      the same block.
     */
    function _syncCashDown() external {
        require(msg.sender == admin, "only the admin may sync cash");
        accrueInterest();

        uint256 balance = EIP20Interface(underlying).balanceOf(address(this));
        if (balance < internalCash) {
            emit CashSynced(internalCash, balance);
            internalCash = balance;
        }
    }

    /*** Safe Token ***/

    /**
     * @notice Gets the lower of internalCash and the underlying balance
     * @dev Immune to direct transfers of underlying to this contract, while a
     *      loss outside the market is priced immediately. View only: a loss
     *      is made permanent only by _syncCashDown or by an implementation
     *      upgrade (_becomeImplementation re-syncs to the balance).
     * @return The quantity of underlying tokens accounted to this market
     */
    function getCashPrior() internal view virtual override returns (uint) {
        uint balance = EIP20Interface(underlying).balanceOf(address(this));
        return balance < internalCash ? balance : internalCash;
    }

    /**
     * @dev Transfers in via MErc20.doTransferIn and credits internalCash with
     *      the amount actually received (fee-on-transfer safe)
     */
    function doTransferIn(
        address from,
        uint amount
    ) internal virtual override returns (uint) {
        uint actualAmount = super.doTransferIn(from, amount);
        internalCash += actualAmount;
        return actualAmount;
    }

    /**
     * @dev Debits internalCash, then transfers out via _transferUnderlyingOut.
     *      Not virtual: subclasses override _transferUnderlyingOut instead.
     */
    function doTransferOut(address payable to, uint amount) internal override {
        internalCash -= amount;
        _transferUnderlyingOut(to, amount);
    }

    /// @dev Moves underlying out of the market; internalCash is already debited
    function _transferUnderlyingOut(
        address payable to,
        uint amount
    ) internal virtual {
        MErc20.doTransferOut(to, amount);
    }
}

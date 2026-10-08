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
     *      existing storage. Updated only by doTransferIn / doTransferOut and
     *      synced to the real balance in _becomeImplementation. Reading this
     *      instead of underlying.balanceOf means direct transfers ("donations")
     *      do not move the exchange rate or count toward supply caps.
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
     * @dev Always syncs internalCash to the underlying balance. Donations are
     *      swept by the outgoing implementation's _resignImplementation first,
     *      so a swap between internal cash implementations absorbs nothing.
     *      Never sweep here: after a legacy implementation internalCash is
     *      unset and the whole balance would look like excess.
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
     * @notice Gets the internally tracked balance of underlying
     * @dev Immune to direct transfers of underlying to this contract
     * @return The quantity of underlying tokens accounted to this market
     */
    function getCashPrior() internal view virtual override returns (uint) {
        return internalCash;
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

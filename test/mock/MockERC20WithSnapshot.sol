// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {ERC20} from "@protocol/stkWell/ERC20.sol";
import {ITransferHook} from "@protocol/stkWell/ITransferHook.sol";

/**
 * @title ERC20WithSnapshot
 * @notice ERC20 including snapshots of balances on transfer-related actions
 * @author Moonwell
 **/
contract MockERC20WithSnapshot is ERC20 {
    /// @dev snapshot of a value on a specific block, used for balances
    struct Snapshot {
        uint128 blockTimestamp;
        uint128 value;
    }

    mapping(address => mapping(uint256 => Snapshot)) public _snapshots;
    mapping(address => uint256) public _countsSnapshots;
    /// @dev reference to the Moonwell governance contract to call (if initialized) on _beforeTokenTransfer
    /// !!! IMPORTANT The Moonwell governance is considered a trustable contract, being its responsibility
    /// to control all potential reentrancies by calling back the this contract
    ITransferHook public _governance;

    event SnapshotDone(address owner, uint128 oldValue, uint128 newValue);

    function _setGovernance(ITransferHook governance) internal virtual {
        _governance = governance;
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The timestamp of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = _countsSnapshots[account];
        return
            nCheckpoints != 0 ? _snapshots[account][nCheckpoints - 1].value : 0;
    }

    /**
     * @notice Determine the prior timestamp of votes for an account as of a block timestamp
     * @dev Block timestamp must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockTimestamp The block timestamp to get the vote balance at
     * @return The timestamp of votes the account had as of the given block
     */
    function getPriorVotes(
        address account,
        uint256 blockTimestamp
    ) external view returns (uint256) {
        require(blockTimestamp < block.number, "not yet determined");

        uint256 nCheckpoints = _countsSnapshots[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (
            _snapshots[account][nCheckpoints - 1].blockTimestamp <=
            blockTimestamp
        ) {
            return _snapshots[account][nCheckpoints - 1].value;
        }

        // Next check implicit zero balance
        if (_snapshots[account][0].blockTimestamp > blockTimestamp) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Snapshot memory cp = _snapshots[account][center];
            if (cp.blockTimestamp == blockTimestamp) {
                return cp.value;
            } else if (cp.blockTimestamp < blockTimestamp) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return _snapshots[account][lower].value;
    }

    /**
     * @dev Writes a snapshot for an owner of tokens
     * @param owner The owner of the tokens
     * @param oldValue The value before the operation that is gonna be executed after the snapshot
     * @param newValue The value after the operation
     */
    function _writeSnapshot(
        address owner,
        uint128 oldValue,
        uint128 newValue
    ) internal virtual {
        uint128 currentBlock = uint128(block.number);

        uint256 ownerCountOfSnapshots = _countsSnapshots[owner];
        mapping(uint256 => Snapshot) storage snapshotsOwner = _snapshots[owner];

        // Doing multiple operations in the same block
        if (
            ownerCountOfSnapshots != 0 &&
            snapshotsOwner[ownerCountOfSnapshots.sub(1)].blockTimestamp ==
            currentBlock
        ) {
            snapshotsOwner[ownerCountOfSnapshots.sub(1)].value = newValue;
        } else {
            snapshotsOwner[ownerCountOfSnapshots] = Snapshot(
                currentBlock,
                newValue
            );
            _countsSnapshots[owner] = ownerCountOfSnapshots.add(1);
        }

        emit SnapshotDone(owner, oldValue, newValue);
    }

    /**
     * @dev Writes a snapshot before any operation involving transfer of value: _transfer, _mint and _burn
     * - On _transfer, it writes snapshots for both "from" and "to"
     * - On _mint, only for _to
     * - On _burn, only for _from
     * @param from the from address
     * @param to the to address
     * @param amount the amount to transfer
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (from == to) {
            return;
        }

        if (from != address(0)) {
            uint256 fromBalance = balanceOf(from);
            _writeSnapshot(
                from,
                uint128(fromBalance),
                uint128(fromBalance.sub(amount))
            );
        }
        if (to != address(0)) {
            uint256 toBalance = balanceOf(to);
            _writeSnapshot(
                to,
                uint128(toBalance),
                uint128(toBalance.add(amount))
            );
        }

        // caching the Moonwell governance address to avoid multiple state loads
        ITransferHook governance = _governance;
        if (governance != ITransferHook(0)) {
            governance.onTransfer(from, to, amount);
        }
    }
}

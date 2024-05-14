// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import {IERC4626} from "@openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {IERC20Permit} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";

import {MarketParams} from "@external/DataStructures.sol";

struct MarketConfig {
    /// @notice The maximum amount of assets that can be allocated to the market.
    uint184 cap;
    /// @notice Whether the market is in the withdraw queue.
    bool enabled;
    /// @notice The timestamp at which the market can be instantly removed from the withdraw queue.
    uint64 removableAt;
}

struct PendingUint192 {
    /// @notice The pending value to set.
    uint192 value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

struct PendingAddress {
    /// @notice The pending value to set.
    address value;
    /// @notice The timestamp at which the pending value becomes valid.
    uint64 validAt;
}

/// @dev Warning: For `feeRecipient`, `supplyShares` does not contain the accrued shares since the last interest
/// accrual.
struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}

/// @dev Warning: `totalSupplyAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalBorrowAssets` does not contain the accrued interest since the last interest accrual.
/// @dev Warning: `totalSupplyShares` does not contain the additional shares accrued by `feeRecipient` since the last
/// interest accrual.
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

struct Signature {
    uint8 v;
    bytes32 r;
    bytes32 s;
}

struct MarketAllocation {
    /// @notice The market to allocate.
    MarketParams marketParams;
    /// @notice The amount of assets to allocate.
    uint256 assets;
}

interface IMulticall {
    function multicall(bytes[] calldata) external returns (bytes[] memory);
}

interface IOwnable {
    function owner() external view returns (address);
    function transferOwnership(address) external;
    function renounceOwnership() external;
    function acceptOwnership() external;
    function pendingOwner() external view returns (address);
}

/// @dev This interface is used for factorizing IMetaMorphoStaticTyping and IMetaMorpho.
/// @dev Consider using the IMetaMorpho interface instead of this one.
interface IMetaMorphoBase {
    /// @notice The address of the Morpho contract.
    function MORPHO() external view returns (address);
    function DECIMALS_OFFSET() external view returns (uint8);

    /// @notice The address of the curator.
    function curator() external view returns (address);

    /// @notice Stores whether an address is an allocator or not.
    function isAllocator(address target) external view returns (bool);

    /// @notice The current guardian. Can be set even without the timelock set.
    function guardian() external view returns (address);

    /// @notice The current fee.
    function fee() external view returns (uint96);

    /// @notice The fee recipient.
    function feeRecipient() external view returns (address);

    /// @notice The skim recipient.
    function skimRecipient() external view returns (address);

    /// @notice The current timelock.
    function timelock() external view returns (uint256);

    /// @dev Stores the order of markets on which liquidity is supplied upon deposit.
    /// @dev Can contain any market. A market is skipped as soon as its supply cap is reached.
    function supplyQueue(uint256) external view returns (bytes32);

    /// @notice Returns the length of the supply queue.
    function supplyQueueLength() external view returns (uint256);

    /// @dev Stores the order of markets from which liquidity is withdrawn upon withdrawal.
    /// @dev Always contain all non-zero cap markets as well as all markets on which the vault supplies liquidity,
    /// without duplicate.
    function withdrawQueue(uint256) external view returns (bytes32);

    /// @notice Returns the length of the withdraw queue.
    function withdrawQueueLength() external view returns (uint256);

    /// @notice Stores the total assets managed by this vault when the fee was last accrued.
    /// @dev May be greater than `totalAssets()` due to removal of markets with non-zero supply or socialized bad debt.
    /// This difference will decrease the fee accrued until one of the functions updating `lastTotalAssets` is
    /// triggered (deposit/mint/withdraw/redeem/setFee/setFeeRecipient).
    function lastTotalAssets() external view returns (uint256);

    /// @notice Submits a `newTimelock`.
    /// @dev Warning: Reverts if a timelock is already pending. Revoke the pending timelock to overwrite it.
    /// @dev In case the new timelock is higher than the current one, the timelock is set immediately.
    function submitTimelock(uint256 newTimelock) external;

    /// @notice Accepts the pending timelock.
    function acceptTimelock() external;

    /// @notice Revokes the pending timelock.
    /// @dev Does not revert if there is no pending timelock.
    function revokePendingTimelock() external;

    /// @notice Submits a `newSupplyCap` for the market defined by `marketParams`.
    /// @dev Warning: Reverts if a cap is already pending. Revoke the pending cap to overwrite it.
    /// @dev Warning: Reverts if a market removal is pending.
    /// @dev In case the new cap is lower than the current one, the cap is set immediately.
    function submitCap(
        MarketParams memory marketParams,
        uint256 newSupplyCap
    ) external;

    /// @notice Accepts the pending cap of the market defined by `marketParams`.
    function acceptCap(MarketParams memory marketParams) external;

    /// @notice Revokes the pending cap of the market defined by `id`.
    /// @dev Does not revert if there is no pending cap.
    function revokePendingCap(bytes32 id) external;

    /// @notice Submits a forced market removal from the vault, eventually losing all funds supplied to the market.
    /// @notice Funds can be recovered by enabling this market again and withdrawing from it (using `reallocate`),
    /// but funds will be distributed pro-rata to the shares at the time of withdrawal, not at the time of removal.
    /// @notice This forced removal is expected to be used as an emergency process in case a market constantly reverts.
    /// To softly remove a sane market, the curator role is expected to bundle a reallocation that empties the market
    /// first (using `reallocate`), followed by the removal of the market (using `updateWithdrawQueue`).
    /// @dev Warning: Removing a market with non-zero supply will instantly impact the vault's price per share.
    /// @dev Warning: Reverts for non-zero cap or if there is a pending cap. Successfully submitting a zero cap will
    /// prevent such reverts.
    function submitMarketRemoval(MarketParams memory marketParams) external;

    /// @notice Revokes the pending removal of the market defined by `id`.
    /// @dev Does not revert if there is no pending market removal.
    function revokePendingMarketRemoval(bytes32 id) external;

    /// @notice Submits a `newGuardian`.
    /// @notice Warning: a malicious guardian could disrupt the vault's operation, and would have the power to revoke
    /// any pending guardian.
    /// @dev In case there is no guardian, the gardian is set immediately.
    /// @dev Warning: Submitting a gardian will overwrite the current pending gardian.
    function submitGuardian(address newGuardian) external;

    /// @notice Accepts the pending guardian.
    function acceptGuardian() external;

    /// @notice Revokes the pending guardian.
    function revokePendingGuardian() external;

    /// @notice Skims the vault `token` balance to `skimRecipient`.
    function skim(address) external;

    /// @notice Sets `newAllocator` as an allocator or not (`newIsAllocator`).
    function setIsAllocator(address newAllocator, bool newIsAllocator) external;

    /// @notice Sets `curator` to `newCurator`.
    function setCurator(address newCurator) external;

    /// @notice Sets the `fee` to `newFee`.
    function setFee(uint256 newFee) external;

    /// @notice Sets `feeRecipient` to `newFeeRecipient`.
    function setFeeRecipient(address newFeeRecipient) external;

    /// @notice Sets `skimRecipient` to `newSkimRecipient`.
    function setSkimRecipient(address newSkimRecipient) external;

    /// @notice Sets `supplyQueue` to `newSupplyQueue`.
    /// @param newSupplyQueue is an array of enabled markets, and can contain duplicate markets, but it would only
    /// increase the cost of depositing to the vault.
    function setSupplyQueue(bytes32[] calldata newSupplyQueue) external;

    /// @notice Updates the withdraw queue. Some markets can be removed, but no market can be added.
    /// @notice Removing a market requires the vault to have 0 supply on it, or to have previously submitted a removal
    /// for this market (with the function `submitMarketRemoval`).
    /// @notice Warning: Anyone can supply on behalf of the vault so the call to `updateWithdrawQueue` that expects a
    /// market to be empty can be griefed by a front-run. To circumvent this, the allocator can simply bundle a
    /// reallocation that withdraws max from this market with a call to `updateWithdrawQueue`.
    /// @dev Warning: Removing a market with supply will decrease the fee accrued until one of the functions updating
    /// `lastTotalAssets` is triggered (deposit/mint/withdraw/redeem/setFee/setFeeRecipient).
    /// @dev Warning: `updateWithdrawQueue` is not idempotent. Submitting twice the same tx will change the queue twice.
    /// @param indexes The indexes of each market in the previous withdraw queue, in the new withdraw queue's order.
    function updateWithdrawQueue(uint256[] calldata indexes) external;

    /// @notice Reallocates the vault's liquidity so as to reach a given allocation of assets on each given market.
    /// @notice The allocator can withdraw from any market, even if it's not in the withdraw queue, as long as the loan
    /// token of the market is the same as the vault's asset.
    /// @dev The behavior of the reallocation can be altered by state changes, including:
    /// - Deposits on the vault that supplies to markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from the vault that withdraws from markets that are expected to be withdrawn from during
    /// reallocation.
    /// - Donations to the vault on markets that are expected to be supplied to during reallocation.
    /// - Withdrawals from markets that are expected to be withdrawn from during reallocation.
    /// @dev Sender is expected to pass `assets = type(uint256).max` with the last MarketAllocation of `allocations` to
    /// supply all the remaining withdrawn liquidity, which would ensure that `totalWithdrawn` = `totalSupplied`.
    function reallocate(MarketAllocation[] calldata allocations) external;
}

/// @dev This interface is inherited by MetaMorpho so that function signatures are checked by the compiler.
/// @dev Consider using the IMetaMorpho interface instead of this one.
interface IMetaMorphoStaticTyping is IMetaMorphoBase {
    /// @notice Returns the current configuration of each market.
    function config(
        bytes32
    ) external view returns (uint184 cap, bool enabled, uint64 removableAt);

    /// @notice Returns the pending guardian.
    function pendingGuardian()
        external
        view
        returns (address guardian, uint64 validAt);

    /// @notice Returns the pending cap for each market.
    function pendingCap(
        bytes32
    ) external view returns (uint192 value, uint64 validAt);

    /// @notice Returns the pending timelock.
    function pendingTimelock()
        external
        view
        returns (uint192 value, uint64 validAt);
}

/// @title IMetaMorpho
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @dev Use this interface for MetaMorpho to have access to all the functions with the appropriate function signatures.
interface IMetaMorpho is
    IMetaMorphoBase,
    IERC4626,
    IERC20Permit,
    IOwnable,
    IMulticall
{
    /// @notice Returns the current configuration of each market.
    function config(bytes32) external view returns (MarketConfig memory);

    /// @notice Returns the pending guardian.
    function pendingGuardian() external view returns (PendingAddress memory);

    /// @notice Returns the pending cap for each market.
    function pendingCap(bytes32) external view returns (PendingUint192 memory);

    /// @notice Returns the pending timelock.
    function pendingTimelock() external view returns (PendingUint192 memory);
}

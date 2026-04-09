// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";

interface IMorphoBlue {
    function createMarket(MarketParams memory marketParams) external;

    /// @notice Supplies `assets` of collateral on behalf of `onBehalf`, optionally calling back the caller's
    /// `onMorphoSupplyCollateral` function with the given `data`.
    /// @dev Interest are not accrued since it's not required and it saves gas.
    /// @dev Supplying a large amount can revert for overflow.
    /// @param marketParams The market to supply collateral to.
    /// @param assets The amount of collateral to supply.
    /// @param onBehalf The address that will own the increased collateral position.
    /// @param data Arbitrary data to pass to the `onMorphoSupplyCollateral` callback. Pass empty data if not needed.
    function supplyCollateral(
        MarketParams memory marketParams,
        uint256 assets,
        address onBehalf,
        bytes memory data
    ) external;

    /// @notice Borrows `assets` or `shares` on behalf of `onBehalf` and sends the assets to `receiver`.
    /// @dev Either `assets` or `shares` should be zero. Most use cases should rely on `assets` as an input so the
    /// caller is guaranteed to borrow `assets` of tokens, but the possibility to mint a specific amount of shares is
    /// given for full compatibility and precision.
    /// @dev `msg.sender` must be authorized to manage `onBehalf`'s positions.
    /// @dev Borrowing a large amount can revert for overflow.
    /// @dev Borrowing an amount of shares may lead to borrow fewer assets than expected due to slippage.
    /// Consider using the `assets` parameter to avoid this.
    /// @param marketParams The market to borrow assets from.
    /// @param assets The amount of assets to borrow.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will own the increased borrow position.
    /// @param receiver The address that will receive the borrowed assets.
    /// @return assetsBorrowed The amount of assets borrowed.
    /// @return sharesBorrowed The amount of shares minted.
    function borrow(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        address receiver
    ) external returns (uint256 assetsBorrowed, uint256 sharesBorrowed);

    /// @notice Liquidates the given `borrower` position.
    /// @dev Either `seizedAssets` or `repaidShares` should be zero.
    /// @dev Liquidating a position with bad debt (ie. with collateral value < borrowed value) will socialize the bad debt.
    /// @param marketParams The market to liquidate in.
    /// @param borrower The address of the borrower to liquidate.
    /// @param seizedAssets The amount of collateral to seize.
    /// @param repaidShares The amount of shares to repay.
    /// @param data Arbitrary data to pass to the liquidation callback. Pass empty if no callback needed.
    /// @return seizedAssets The amount of collateral seized.
    /// @return repaidAssets The amount of assets repaid.
    function liquidate(
        MarketParams memory marketParams,
        address borrower,
        uint256 seizedAssets,
        uint256 repaidShares,
        bytes memory data
    ) external returns (uint256, uint256);

    /// @notice Supplies assets or shares on behalf of onBehalf, optionally calling back the caller's onMorphoSupply
    /// function with the given data.
    /// @dev Either assets or shares should be zero.
    /// @param marketParams The market to supply assets to.
    /// @param assets The amount of assets to supply.
    /// @param shares The amount of shares to mint.
    /// @param onBehalf The address that will own the increased supply position.
    /// @param data Arbitrary data to pass to the onMorphoSupply callback. Pass empty data if not needed.
    /// @return assetsSupplied The amount of assets supplied.
    /// @return sharesSupplied The amount of shares minted.
    function supply(
        MarketParams memory marketParams,
        uint256 assets,
        uint256 shares,
        address onBehalf,
        bytes memory data
    ) external returns (uint256 assetsSupplied, uint256 sharesSupplied);
}

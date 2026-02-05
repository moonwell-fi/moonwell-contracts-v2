// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

/// @notice Market parameters used by Morpho Blue
struct MorphoMarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

/// @notice Market state in Morpho Blue
struct MorphoMarket {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}

/// @notice Interface for Morpho Vault V2 (adapter-based architecture)
interface IMorphoVaultV2 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function adapterRegistry() external view returns (address);
    function adaptersLength() external view returns (uint256);
    function adapters(uint256 index) external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
}

/// @notice Interface for Vault V2 Adapters
interface IVaultV2Adapter {
    function realAssets() external view returns (uint256);
    function morphoVaultV1() external view returns (address);
}

/// @notice Interface for MetaMorpho (underlying vault)
interface IMetaMorphoV2 {
    function MORPHO() external view returns (address);
    function asset() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function fee() external view returns (uint96);
    function timelock() external view returns (uint256);
    function withdrawQueueLength() external view returns (uint256);
    function withdrawQueue(uint256 index) external view returns (bytes32);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

/// @notice Interface for Morpho Blue (V2 compatible with bytes32)
interface IMorphoBlueV2 {
    function idToMarketParams(
        bytes32 id
    ) external view returns (MorphoMarketParams memory);

    function market(bytes32 id) external view returns (MorphoMarket memory);
}

/// @notice Interface for IRM (Interest Rate Model)
interface IIrmV2 {
    function borrowRateView(
        MorphoMarketParams memory marketParams,
        MorphoMarket memory market
    ) external view returns (uint256);
}

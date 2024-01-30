// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

interface IEcosystemReserveUplift {
    /// @notice Initialize function, sets ecosystem reserve, callable only once
    function initialize(address reserveController) external;

    /// @notice approve tokens from ecosystem reserve to recipient
    function approve(address token, address recipient, uint256 amount) external;

    /// @notice transfer tokens from ecosystem reserve to recipient
    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) external;

    /// @notice set funds admin
    function setFundsAdmin(address admin) external;

    /// @notice get the funds admin
    function getFundsAdmin() external view returns (address);
}

interface IEcosystemReserveControllerUplift {
    /// @notice approve tokens from ecosystem reserve to recipient
    function approve(address token, address recipient, uint256 amount) external;

    /// @notice transfer tokens from ecosystem reserve to recipient
    function transfer(
        address token,
        address recipient,
        uint256 amount
    ) external;

    /// @notice set funds admin
    function setFundsAdmin(address admin) external;

    /// @notice Initialize function, sets ecosystem reserve, callable only once
    function setEcosystemReserve() external view returns (address);

    /// @notice returns reference to ecosystem reserve controller
    function ECOSYSTEM_RESERVE() external view returns (address);

    /// @notice returns owner address
    function transferOwnership(address newOwner) external returns (address);

    /// @notice returns owner address
    function owner() external view returns (address);

    /// @notice returns true if ecosystem reserve has been initialized
    function initialized() external view returns (bool);
}

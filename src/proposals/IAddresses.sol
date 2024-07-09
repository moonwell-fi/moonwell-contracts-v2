// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

/// @notice This is a contract that stores addresses for different networks.
/// It allows a project to have a single source of truth to get all the addresses
/// for a given network.
interface IAddresses {
    /// @notice check if an address is set
    /// @param name the name of the address
    function isAddressSet(string memory name) external view returns (bool);

    /// @notice check if an address is set for a specific chain id
    /// @param name the name of the address
    /// @param chainId the chain id
    function isAddressSet(string memory name, uint256 chainId)
        external
        view
        returns (bool);

    /// @notice check if an address is a contract
    /// @param name the name of the address
    function isAddressContract(string memory name)
        external
        view
        returns (bool);

    /// @notice get an address for the current chainId
    function getAddress(string memory name) external view returns (address);

    /// @notice get an address for a specific chainId
    function getAddress(string memory name, uint256 _chainId)
        external
        view
        returns (address);

    /// @notice add a contract address for the current chainId
    function addAddress(string memory name, address addr) external;

    /// @notice add an EOA address for the current chainId
    function addAddressEOA(string memory name, address addr) external;

    /// @notice add an EOA address to the specified chainId
    function addAddressEOA(string memory name, address addr, uint256 chainId)
        external;

    /// @notice add an address for a specific chainId
    function addAddress(
        string memory name,
        address addr,
        uint256 _chainId,
        bool isContract
    ) external;

    /// @notice change an address for the current chainId
    function changeAddress(string memory name, address addr, bool isContract)
        external;

    /// @notice change an address for an specific chainId and change the isContract flag
    function changeAddress(
        string memory name,
        address _addr,
        uint256 _chainId,
        bool isContract
    ) external;

    /// @notice remove recorded addresses
    function resetRecordingAddresses() external;

    /// @notice remove changed addresses
    function resetChangedAddresses() external;

    /// @notice get recorded addresses from a proposal's deployment
    function getRecordedAddresses()
        external
        view
        returns (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory addresses
        );

    /// @notice get changed addresses from a proposal
    function getChangedAddresses()
        external
        view
        returns (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory oldAddresses,
            address[] memory newAddresses
        );
}

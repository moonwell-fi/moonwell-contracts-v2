// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

/// @notice This is a contract that stores addresses for different networks.
/// It allows a project to have a single source of truth to get all the addresses
/// for a given network.
contract Addresses is Test {
    /// @notice mapping from contract name to network chain id to address
    mapping(string => mapping(uint256 => address)) _addresses;

    /// @notice chainid of the network when contract is constructed
    uint256 public immutable chainId;

    /// @notice json structure to read addresses into storage from file
    struct SavedAddresses {
        /// address to store
        address addr;
        /// chain id of network to store for
        uint256 chainId;
        /// name of contract to store
        string name;
    }

    /// @notice struct to record addresses deployed during a proposal
    struct RecordedAddress {
        string name;
        address addr;
    }

    /// @notice array of addresses deployed during a proposal
    RecordedAddress[] private recordedAddresses;
    string public addressesPath = "./utils/Addresses.json";

    constructor() {
        chainId = block.chainid;

        string memory addressesData = string(
            abi.encodePacked(vm.readFile(addressesPath))
        );

        bytes memory parsedJson = vm.parseJson(addressesData);

        SavedAddresses[] memory savedAddresses = abi.decode(
            parsedJson,
            (SavedAddresses[])
        );

        for (uint256 i = 0; i < savedAddresses.length; i++) {
            require(
                getAddress(savedAddresses[i].name, savedAddresses[i].chainId) ==
                    address(0),
                "Addresses: duplicate address in json"
            );

            _addAddress(
                savedAddresses[i].name,
                savedAddresses[i].chainId,
                savedAddresses[i].addr
            );
        }
    }

    /// @notice add an address for a specific chainId
    function _addAddress(
        string memory name,
        uint256 _chainId,
        address addr
    ) private {
        require(
            _addresses[name][_chainId] == address(0),
            string(abi.encodePacked("Addresses: duplicate address: ", name))
        );
        _addresses[name][_chainId] = addr;
        vm.label(addr, name);
    }

    /// @notice add an address for the current chainId
    function _addAddress(string memory name, address addr) private {
        _addAddress(name, chainId, addr);
    }

    /// @notice get an address for the current chainId
    function getAddress(string memory name) public view returns (address) {
        return _addresses[name][chainId];
    }

    /// @notice get an address for a specific chainId
    function getAddress(
        string memory name,
        uint256 _chainId
    ) public view returns (address) {
        return _addresses[name][_chainId];
    }

    /// @notice add an address for the current chainId
    function addAddress(string memory name, address addr) public {
        _addAddress(name, addr);

        recordedAddresses.push(RecordedAddress({name: name, addr: addr}));
    }

    /// @notice add an address for the current chainId
    function addAddress(
        string memory name,
        address addr,
        uint256 _chainId
    ) public {
        _addAddress(name, _chainId, addr);

        recordedAddresses.push(RecordedAddress({name: name, addr: addr}));
    }

    /// @notice remove recorded addresses
    function resetRecordingAddresses() external {
        delete recordedAddresses;
    }

    /// @notice get recorded addresses from a proposal's deployment
    function getRecordedAddresses()
        external
        view
        returns (string[] memory names, address[] memory addresses)
    {
        names = new string[](recordedAddresses.length);
        addresses = new address[](recordedAddresses.length);
        for (uint256 i = 0; i < recordedAddresses.length; i++) {
            names[i] = recordedAddresses[i].name;
            addresses[i] = recordedAddresses[i].addr;
        }
    }
}

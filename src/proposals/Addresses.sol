// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {IAddresses} from "./IAddresses.sol";
import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";

contract Addresses is IAddresses, Test {
    using Strings for uint256;

    /// @notice mapping from contract name to network chain id to address
    mapping(string name => mapping(uint256 chainId => address addr))
        public _addresses;

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
        uint256 chainId;
    }

    // @notice struct to record addresses changed during a proposal
    struct ChangedAddress {
        string name;
        uint256 chainId;
        address oldAddress;
    }

    /// @notice array of addresses deployed during a proposal
    RecordedAddress[] private recordedAddresses;

    // @notice array of addresses changed during a proposal
    ChangedAddress[] private changedAddresses;

    string public addressesPath = "./utils/Addresses.json";

    constructor() {
        string memory addressesData = string(
            abi.encodePacked(vm.readFile(addressesPath))
        );

        bytes memory parsedJson = vm.parseJson(addressesData);

        SavedAddresses[] memory savedAddresses = abi.decode(
            parsedJson,
            (SavedAddresses[])
        );

        for (uint256 i = 0; i < savedAddresses.length; i++) {
            _addAddress(
                savedAddresses[i].name,
                savedAddresses[i].addr,
                savedAddresses[i].chainId
            );
        }
    }

    /// @notice add an address for a specific chainId
    function _addAddress(
        string memory name,
        address addr,
        uint256 _chainId
    ) private {
        address currentAddress = _addresses[name][_chainId];

        require(
            currentAddress == address(0),
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " already set on chain: ",
                    _chainId.toString()
                )
            )
        );

        _addresses[name][_chainId] = addr;
        vm.label(addr, name);
    }

    function _getAddress(
        string memory name,
        uint256 _chainId
    ) private view returns (address addr) {
        require(_chainId != 0, "ChainId cannot be 0");

        addr = _addresses[name][_chainId];

        // ignore localnet
        if (_chainId != 31337) {
            require(
                addr != address(0),
                string(
                    abi.encodePacked(
                        "Address: ",
                        name,
                        " not set on chain: ",
                        _chainId.toString()
                    )
                )
            );
        }
    }

    /// @notice get an address for the current chainId
    function getAddress(string memory name) public view returns (address) {
        return _getAddress(name, block.chainid);
    }

    /// @notice get an address for a specific chainId
    function getAddress(
        string memory name,
        uint256 _chainId
    ) public view returns (address) {
        return _getAddress(name, _chainId);
    }

    /// @notice add an address for the current chainId
    function addAddress(string memory name, address addr) public {
        _addAddress(name, addr, block.chainid);

        recordedAddresses.push(
            RecordedAddress({name: name, chainId: block.chainid})
        );
    }

    /// @notice add an address for a specific chainId
    function addAddress(
        string memory name,
        address addr,
        uint256 _chainId
    ) public {
        _addAddress(name, addr, _chainId);

        recordedAddresses.push(
            RecordedAddress({name: name, chainId: _chainId})
        );
    }

    /// @notice change an address for a specific chainId
    function changeAddress(
        string memory name,
        address _addr,
        uint256 _chainId
    ) public {
        address addr = _addresses[name][_chainId];
        require(
            addr != address(0),
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " doesn't exist on chain: ",
                    _chainId.toString(),
                    ". Use addAddress instead"
                )
            )
        );

        require(
            addr != _addr,
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " already set to the same value on chain: ",
                    _chainId.toString()
                )
            )
        );

        changedAddresses.push(
            ChangedAddress({name: name, chainId: _chainId, oldAddress: addr})
        );

        _addresses[name][_chainId] = _addr;
        vm.label(_addr, name);
    }

    /// @notice change an address for the current chainId
    function changeAddress(string memory name, address addr) public {
        changeAddress(name, addr, block.chainid);
    }

    /// @notice remove recorded addresses
    function resetRecordingAddresses() external {
        delete recordedAddresses;
    }

    /// @notice get recorded addresses from a proposal's deployment
    function getRecordedAddresses()
        external
        view
        returns (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory addresses
        )
    {
        uint256 length = recordedAddresses.length;
        names = new string[](length);
        chainIds = new uint256[](length);
        addresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            names[i] = recordedAddresses[i].name;
            chainIds[i] = recordedAddresses[i].chainId;
            addresses[i] = _addresses[recordedAddresses[i].name][
                recordedAddresses[i].chainId
            ];
        }
    }

    /// @notice remove changed addresses
    function resetChangedAddresses() external {
        delete changedAddresses;
    }

    /// @notice get changed addresses from a proposal's deployment
    function getChangedAddresses()
        external
        view
        returns (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory oldAddresses,
            address[] memory newAddresses
        )
    {
        uint256 length = changedAddresses.length;
        names = new string[](length);
        chainIds = new uint256[](length);
        oldAddresses = new address[](length);
        newAddresses = new address[](length);

        for (uint256 i = 0; i < length; i++) {
            names[i] = changedAddresses[i].name;
            chainIds[i] = changedAddresses[i].chainId;
            oldAddresses[i] = changedAddresses[i].oldAddress;
            newAddresses[i] = _addresses[changedAddresses[i].name][
                changedAddresses[i].chainId
            ];
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Strings} from "@openzeppelin-contracts/contracts/utils/Strings.sol";
import {EnumerableSet} from
    "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {Test} from "@forge-std/Test.sol";

import {IAddresses} from "./IAddresses.sol";

/// @notice This is a contract that stores addresses for different networks.
/// It allows a project to have a single source of truth to get all the addresses
/// for a given network.
contract Addresses is IAddresses, Test {
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    struct Address {
        address addr;
        bool isContract;
    }

    /// @notice mapping from contract name to network chain id to address
    mapping(string name => mapping(uint256 chainId => Address)) public
        _addresses;

    /// @notice json structure to read addresses into storage from file
    struct SavedAddresses {
        /// address to store
        address addr;
        /// whether the address is a contract
        bool isContract;
        /// name of contract to store
        string name;
    }

    /// @notice struct to record addresses deployed during a proposal
    struct RecordedAddress {
        string name;
        uint256 chainId;
    }

    /// @notice struct to record addresses changed during a proposal
    struct ChangedAddress {
        string name;
        uint256 chainId;
        address oldAddress;
    }

    /// @notice array of addresses deployed during a proposal
    RecordedAddress[] private recordedAddresses;

    /// @notice array of addresses changed during a proposal
    ChangedAddress[] private changedAddresses;

    /// @notice all allowed chain IDs. Empty when all chain IDs are allowed
    EnumerableSet.UintSet[] private _allowedChainIds;

    constructor(uint256[] memory chainids) {
        string memory projectRoot = vm.projectRoot();

        for (uint256 j = 0; j < chainids.length; j++) {
            /// fetch <chainid>.json file path and read its raw contents
            string memory data = vm.readFile(
                string(
                    abi.encodePacked(
                        projectRoot,
                        "/utils/",
                        vm.toString(chainids[j]),
                        ".json"
                    )
                )
            );
            bytes memory parsedJson = vm.parseJson(data);

            SavedAddresses[] memory savedAddresses =
                abi.decode(parsedJson, (SavedAddresses[]));

            uint256 length = savedAddresses.length;
            uint256 chainId = chainids[j];

            for (uint256 i = 0; i < length; i++) {
                _addAddress(
                    savedAddresses[i].name,
                    savedAddresses[i].addr,
                    chainId,
                    savedAddresses[i].isContract
                );
            }
        }
    }

    /// Address Restrictions

    /// @notice view function to return the number of restrictions on the stack
    function restrictionLength() public view returns (uint256) {
        return _allowedChainIds.length;
    }

    /// @notice function to remove all restrictions on which chainIds this
    /// contract can be used for.
    function removeAllRestrictions() public {
        /// iterate over each chain id and remove it
        while (_allowedChainIds.length != 0) {
            while (_allowedChainIds[0].length() != 0) {
                _allowedChainIds[0].remove(_allowedChainIds[0].at(0));
            }
            _allowedChainIds.pop();
        }
    }

    /// @notice function to remove the current restriction on which chainIds
    /// this contract can be used for.
    function removeRestriction() public {
        _allowedChainIds.pop();
    }

    /// @notice function to add restrictions on which chainIds this contract
    /// can be used for.
    /// @param allowedChainId the chain id to allow usage on
    function addRestriction(uint256 allowedChainId) public {
        _allowedChainIds.push();
        _allowedChainIds[_allowedChainIds.length - 1].add(allowedChainId);
    }

    /// @notice function to add restrictions on which chainIds this contract
    /// can be used for.
    /// @param allowedChainIds the chain ids to allow usage on
    function addRestrictions(uint256[] memory allowedChainIds) public {
        require(allowedChainIds.length > 0, "ChainIds to add cannot be empty");
        _allowedChainIds.push();

        for (uint256 i = 0; i < allowedChainIds.length; i++) {
            _allowedChainIds[_allowedChainIds.length - 1].add(
                allowedChainIds[i]
            );
        }
    }

    /// @notice function to check if a chainId is allowed to be accessed
    /// returns true if the chainId restriction at the top of the stack is
    /// in the restriction.
    /// @notice Returns true if there are no restrictions.
    function chainIdAllowed(uint256 chainId) public view returns (bool) {
        return _allowedChainIds.length == 0
            || _allowedChainIds[_allowedChainIds.length - 1].contains(chainId);
    }

    /// @notice helper function to check if a chainId is allowed to be accessed
    /// @param chainId the chain id to check
    function _restrictionCheck(uint256 chainId) private view {
        require(
            chainIdAllowed(chainId),
            string(
                abi.encodePacked(
                    "ChainIds are restricted from using chainId: ",
                    vm.toString(chainId)
                )
            )
        );
    }

    /// @notice get an address for the current chainId
    /// @param name the name of the address
    function getAddress(string memory name) public view returns (address) {
        return _getAddress(name, block.chainid);
    }

    /// @notice get an address for a specific chainId
    /// @param name the name of the address
    /// @param _chainId the chain id
    function getAddress(string memory name, uint256 _chainId)
        public
        view
        returns (address)
    {
        return _getAddress(name, _chainId);
    }

    /// it is assumed that all addresses added through this method are
    /// contracts. any non contract address should be added through the
    /// corresponding json file.
    /// @notice add an address for the current chainId
    /// @param name the name of the address
    /// @param addr the address to add
    function addAddress(string memory name, address addr) public override {
        _addAddress(name, addr, block.chainid, true);

        recordedAddresses.push(
            RecordedAddress({name: name, chainId: block.chainid})
        );
    }

    /// @notice it is assumed that all addresses added through this method are
    /// EOA's (without bytecode). any contract address should be added through
    /// the addAddress method.
    /// @notice add an address for the current chainId
    /// @param name the name of the address
    /// @param addr the address to add
    function addAddressEOA(string memory name, address addr) public override {
        addAddressEOA(name, addr, block.chainid);
    }

    /// @notice it is assumed that all addresses added through this method are
    /// EOA's (without bytecode). any contract address should be added through
    /// the addAddress method.
    /// @notice add an address for the current chainId
    /// @param name the name of the address
    /// @param addr the address to add
    /// @param chainId the chain id to add the address
    function addAddressEOA(string memory name, address addr, uint256 chainId)
        public
        override
    {
        _addAddress(name, addr, chainId, false);

        recordedAddresses.push(RecordedAddress({name: name, chainId: chainId}));
    }

    /// @notice add an address for a specific chainId
    /// @param name the name of the address
    /// @param addr the address to add
    /// @param _chainId the chain id
    /// @param isContract whether the address is a contract
    function addAddress(
        string memory name,
        address addr,
        uint256 _chainId,
        bool isContract
    ) public {
        _addAddress(name, addr, _chainId, isContract);

        recordedAddresses.push(RecordedAddress({name: name, chainId: _chainId}));
    }

    /// @notice change an address for a specific chainId
    /// @param name the name of the address
    /// @param _addr the address to change to
    /// @param chainId the chain id
    /// @param isContract whether the address is a contract
    function changeAddress(
        string memory name,
        address _addr,
        uint256 chainId,
        bool isContract
    ) public {
        Address storage data = _addresses[name][chainId];

        require(_addr != address(0), "Address cannot be 0");

        require(chainId != 0, "ChainId cannot be 0");

        require(
            data.addr != address(0),
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " doesn't exist on chain: ",
                    chainId.toString(),
                    ". Use addAddress instead"
                )
            )
        );

        require(
            data.addr != _addr,
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " already set to the same value on chain: ",
                    chainId.toString()
                )
            )
        );

        _checkAddress(_addr, isContract, name, chainId);

        changedAddresses.push(
            ChangedAddress({name: name, chainId: chainId, oldAddress: data.addr})
        );

        data.addr = _addr;
        data.isContract = isContract;
        vm.label(_addr, name);
    }

    /// @notice change an address for the current chainId
    /// @param name the name of the address
    /// @param addr the address to change to
    /// @param isContract whether the address is a contract
    function changeAddress(string memory name, address addr, bool isContract)
        public
    {
        _restrictionCheck(block.chainid);

        changeAddress(name, addr, block.chainid, isContract);
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
            addresses[i] = _addresses[recordedAddresses[i].name][recordedAddresses[i]
                .chainId].addr;
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
            newAddresses[i] = _addresses[changedAddresses[i].name][changedAddresses[i]
                .chainId].addr;
        }
    }

    /// @notice check if an address is a contract
    /// @param name the name of the address
    function isAddressContract(string memory name) public view returns (bool) {
        _restrictionCheck(block.chainid);
        return _addresses[name][block.chainid].isContract;
    }

    /// @notice check if an address is set
    /// @param name the name of the address
    function isAddressSet(string memory name) public view returns (bool) {
        _restrictionCheck(block.chainid);
        return isAddressSet(name, block.chainid);
    }

    /// @notice check if an address is set for a specific chain id
    /// @param name the name of the address
    /// @param chainId the chain id
    function isAddressSet(string memory name, uint256 chainId)
        public
        view
        returns (bool)
    {
        _restrictionCheck(chainId);

        return _addresses[name][chainId].addr != address(0);
    }

    /// @notice add an address for a specific chainId
    /// @param name the name of the address
    /// @param addr the address to add
    /// @param chainId the chain id
    /// @param isContract whether the address is a contract
    function _addAddress(
        string memory name,
        address addr,
        uint256 chainId,
        bool isContract
    ) private {
        Address storage currentAddress = _addresses[name][chainId];

        require(addr != address(0), "Address cannot be 0");

        require(chainId != 0, "ChainId cannot be 0");

        require(
            currentAddress.addr == address(0),
            string(
                abi.encodePacked(
                    "Address: ",
                    name,
                    " already set on chain: ",
                    chainId.toString()
                )
            )
        );

        _checkAddress(addr, isContract, name, chainId);

        currentAddress.addr = addr;
        currentAddress.isContract = isContract;

        vm.label(addr, name);
    }

    /// @notice get an address for a specific chainId
    /// @param name the name of the address
    /// @param chainId the chain id
    function _getAddress(string memory name, uint256 chainId)
        private
        view
        returns (address addr)
    {
        require(chainId != 0, "ChainId cannot be 0");

        Address memory data = _addresses[name][chainId];
        addr = data.addr;

        require(
            addr != address(0),
            string(
                abi.encodePacked(
                    "Address: ", name, " not set on chain: ", chainId.toString()
                )
            )
        );

        _checkAddress(addr, data.isContract, name, chainId);
    }

    /// @notice check if an address is a contract
    /// @param _addr the address to check
    /// @param isContract whether the address is a contract
    /// @param name the name of the address
    /// @param chainId the chain id
    function _checkAddress(
        address _addr,
        bool isContract,
        string memory name,
        uint256 chainId
    ) private view {
        _restrictionCheck(chainId);

        if (chainId == block.chainid) {
            if (isContract) {
                require(
                    _addr.code.length > 0,
                    string(
                        abi.encodePacked(
                            "Address: ",
                            name,
                            " is not a contract on chain: ",
                            chainId.toString()
                        )
                    )
                );
            } else {
                require(
                    _addr.code.length == 0,
                    string(
                        abi.encodePacked(
                            "Address: ",
                            name,
                            " is a contract on chain: ",
                            chainId.toString()
                        )
                    )
                );
            }
        }
    }
}

contract AllChainAddresses is Addresses {
    uint256[] public supportedChainIds =
        [8453, 84532, 1285, 1284, 1287, 11155111, 11155420, 31337, 10];

    constructor() Addresses(supportedChainIds) {}
}

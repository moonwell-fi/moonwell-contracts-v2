// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {Test} from "@forge-std/Test.sol";
import {Addresses} from "@proposals/Addresses.sol";

contract UnitTestAddresses is Test {
    Addresses public addresses;

    bytes public parsedJson;

    /// @notice json structure to read addresses into storage from file
    struct SavedAddresses {
        /// address to store
        address addr;
        /// whether the address is a contract
        bool isContract;
        /// name of contract to store
        string name;
    }

    function setUp() public {
        uint256[] memory addressesPath = new uint256[](1);
        addressesPath[0] = 31337;

        addresses = new Addresses(addressesPath);

        string memory addressesData =
            string(abi.encodePacked(vm.readFile("./utils/31337.json")));
        parsedJson = vm.parseJson(addressesData);
    }

    function testGetAddress() public view {
        address addr = addresses.getAddress("EMISSIONS_ADMIN");

        assertEq(addr, 0xD791292655A1d382FcC1a6Cb9171476cf91F2caa);
    }

    function testGetAddressChainId() public view {
        address addr = addresses.getAddress("EMISSIONS_ADMIN", block.chainid);

        assertEq(addr, 0xD791292655A1d382FcC1a6Cb9171476cf91F2caa);
    }

    function testChangeAddress() public {
        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN"),
            0xD791292655A1d382FcC1a6Cb9171476cf91F2caa,
            "Wrong current address"
        );

        address addr = vm.addr(1);
        addresses.changeAddress("EMISSIONS_ADMIN", addr, false);

        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN"),
            addr,
            "Not updated correclty"
        );
    }

    function testChangeAddressToSameAddressFails() public {
        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN"),
            0xD791292655A1d382FcC1a6Cb9171476cf91F2caa,
            "Wrong current address"
        );

        address addr = addresses.getAddress("EMISSIONS_ADMIN");
        vm.expectRevert(
            "Address: EMISSIONS_ADMIN already set to the same value on chain: 31337"
        );
        addresses.changeAddress("EMISSIONS_ADMIN", addr, true);
    }

    function testChangeAddressChainId() public {
        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN"),
            0xD791292655A1d382FcC1a6Cb9171476cf91F2caa,
            "Wrong current address"
        );
        address addr = vm.addr(1);
        uint256 chainId = block.chainid;

        addresses.changeAddress("EMISSIONS_ADMIN", addr, chainId, false);

        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN", chainId),
            addr,
            "Not updated correclty"
        );
    }

    function testAddAddress() public {
        address addr = vm.addr(1);
        addresses.addAddressEOA("TEST", addr);

        assertEq(addresses.getAddress("TEST"), addr);
    }

    function testAddAddressChainId() public {
        address addr = vm.addr(1);
        uint256 chainId = 123;
        addresses.addAddress("TEST", addr, chainId, true);

        assertEq(addresses.getAddress("TEST", chainId), addr);
    }

    function testAddAddressDifferentChain() public {
        address addr = vm.addr(1);
        uint256 chainId = 123;
        addresses.addAddress("EMISSIONS_ADMIN", addr, chainId, true);

        assertEq(addresses.getAddress("EMISSIONS_ADMIN", chainId), addr);
        /// Validate that the 'EMISSIONS_ADMIN' address for chain 31337 matches
        /// the address from Addresses.json.
        assertEq(
            addresses.getAddress("EMISSIONS_ADMIN", 31337),
            0xD791292655A1d382FcC1a6Cb9171476cf91F2caa
        );
    }

    function testResetRecordingAddresses() public {
        addresses.resetRecordingAddresses();

        (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory _addresses
        ) = addresses.getRecordedAddresses();

        assertEq(names.length, 0);
        assertEq(chainIds.length, 0);
        assertEq(_addresses.length, 0);
    }

    function testGetRecordingAddresses() public {
        // Add a new address
        address addr = vm.addr(1);
        addresses.addAddressEOA("TEST", addr);

        (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory _addresses
        ) = addresses.getRecordedAddresses();

        assertEq(names.length, 1);
        assertEq(chainIds.length, 1);
        assertEq(_addresses.length, 1);

        assertEq(names[0], "TEST");
        assertEq(chainIds[0], 31337);
        assertEq(_addresses[0], addr);
    }

    function testResetChangedAddresses() public {
        addresses.resetChangedAddresses();

        (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory oldAddresses,
            address[] memory newAddresses
        ) = addresses.getChangedAddresses();

        assertEq(names.length, 0);
        assertEq(chainIds.length, 0);
        assertEq(oldAddresses.length, 0);
        assertEq(newAddresses.length, 0);
    }

    function testGetChangedAddresses() public {
        address addr = vm.addr(1);
        addresses.changeAddress("EMISSIONS_ADMIN", addr, false);
        (
            string[] memory names,
            uint256[] memory chainIds,
            address[] memory oldAddresses,
            address[] memory newAddresses
        ) = addresses.getChangedAddresses();

        assertEq(names.length, 1);
        assertEq(chainIds.length, 1);
        assertEq(oldAddresses.length, 1);
        assertEq(newAddresses.length, 1);

        SavedAddresses[] memory savedAddresses =
            abi.decode(parsedJson, (SavedAddresses[]));

        assertEq(names[0], savedAddresses[0].name);
        assertEq(chainIds[0], block.chainid);
        assertEq(oldAddresses[0], savedAddresses[0].addr);
        assertEq(newAddresses[0], addr);
    }

    function testRevertGetAddressChainZero() public {
        vm.expectRevert("ChainId cannot be 0");
        addresses.getAddress("EMISSIONS_ADMIN", 0);
    }

    function testReverGetAddressNotSet() public {
        vm.expectRevert("Address: TEST not set on chain: 31337");
        addresses.getAddress("TEST");
    }

    function testReverGetAddressNotSetOnChain() public {
        vm.expectRevert("Address: EMISSIONS_ADMIN not set on chain: 666");
        addresses.getAddress("EMISSIONS_ADMIN", 666);
    }

    function testRevertAddAddressAlreadySet() public {
        vm.expectRevert("Address: EMISSIONS_ADMIN already set on chain: 31337");
        addresses.addAddressEOA("EMISSIONS_ADMIN", vm.addr(1));
    }

    function testRevertAddAddressChainAlreadySet() public {
        vm.expectRevert("Address: EMISSIONS_ADMIN already set on chain: 31337");
        addresses.addAddressEOA("EMISSIONS_ADMIN", vm.addr(1), 31337);
    }

    function testRevertChangedAddressDoesNotExist() public {
        vm.expectRevert(
            "Address: TEST doesn't exist on chain: 31337. Use addAddress instead"
        );
        addresses.changeAddress("TEST", vm.addr(1), false);
    }

    function testAddAddressCannotBeZero() public {
        vm.expectRevert("Address cannot be 0");
        addresses.addAddressEOA("EMISSIONS_ADMIN", address(0));
    }

    function testAddAddressCannotBeZeroChainId() public {
        vm.expectRevert("ChainId cannot be 0");
        addresses.addAddressEOA("EMISSIONS_ADMIN", vm.addr(1), 0);
    }

    function testRevertChangeAddressCannotBeZero() public {
        vm.expectRevert("Address cannot be 0");
        addresses.changeAddress("EMISSIONS_ADMIN", address(0), false);
    }

    function testRevertChangeAddresCannotBeZeroChainId() public {
        vm.expectRevert("ChainId cannot be 0");
        addresses.changeAddress("EMISSIONS_ADMIN", vm.addr(1), 0, false);
    }

    function testIsContractFalse() public view {
        assertEq(addresses.isAddressContract("EMISSIONS_ADMIN"), false);
    }

    function testIsContractTrue() public {
        address test = vm.addr(1);

        vm.etch(test, "0x01");

        addresses.addAddress("TEST", test);

        assertEq(addresses.isAddressContract("TEST"), true);
    }

    function testAddressIsPresent() public {
        address test = vm.addr(1);

        addresses.addAddressEOA("TEST", test);

        assertEq(addresses.isAddressSet("TEST"), true);
    }

    function testAddressIsNotPresent() public view {
        assertFalse(addresses.isAddressSet("TEST"));
    }

    function testAddressIsPresentOnChain() public {
        address test = vm.addr(1);

        addresses.addAddress("TEST", test, 123, false);

        assertEq(addresses.isAddressSet("TEST", 123), true);
    }

    function testAddressIsNotPresentOnChain() public view {
        assertTrue(addresses.isAddressSet("EMISSIONS_ADMIN", 31337));
        assertFalse(addresses.isAddressSet("EMISSIONS_ADMIN", 123));
    }

    function testCheckAddressRevertIfNotContract() public {
        vm.expectRevert("Address: TEST is not a contract on chain: 31337");
        addresses.addAddress("TEST", vm.addr(1));
    }

    function testCheckAddressRevertIfSetIsContractFalseButIsContract() public {
        address test = vm.addr(1);

        vm.etch(test, "0x01");

        vm.expectRevert("Address: TEST is a contract on chain: 31337");
        addresses.addAddressEOA("TEST", test);
    }

    function testAddingSameAddressToSameChainFails() public {
        testAddressIsPresentOnChain();
        address test = vm.addr(1);

        vm.expectRevert("Address: TEST already set on chain: 123");
        addresses.addAddressEOA("TEST", test, 123);
    }

    function testCanRemoveAllRestrictions() public {
        /// no-op on empty restriction set
        addresses.removeAllRestrictions();

        addresses.addRestriction(123);
        addresses.removeAllRestrictions();

        assertEq(
            addresses.restrictionLength(),
            0,
            "restriction length should be zero"
        );

        addresses.addRestriction(123);
        addresses.addRestriction(1234);
        addresses.removeAllRestrictions();

        assertEq(
            addresses.restrictionLength(),
            0,
            "restriction length should be zero"
        );

        uint256[] memory allowedChainIds = new uint256[](3);
        allowedChainIds[0] = 123;
        allowedChainIds[1] = 1234;
        allowedChainIds[2] = 12345;

        addresses.addRestrictions(allowedChainIds);
        assertEq(
            addresses.restrictionLength(), 1, "restriction length should be one"
        );

        addresses.removeAllRestrictions();

        assertEq(
            addresses.restrictionLength(),
            0,
            "restriction length should be zero"
        );
    }

    function testCannotAddAddressRestrictedChain() public {
        addresses.addRestriction(123);

        vm.expectRevert("ChainIds are restricted from using chainId: 31337");
        addresses.addAddress("TEST", vm.addr(1));
    }

    function testCannotChangeAddressRestrictedChain() public {
        addresses.addAddressEOA("TEST", vm.addr(1));

        addresses.addRestriction(123);

        vm.expectRevert("ChainIds are restricted from using chainId: 31337");
        addresses.changeAddress("TEST", vm.addr(1), false);
    }
}

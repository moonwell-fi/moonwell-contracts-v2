//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {BridgeValidationHook} from "@proposals/hooks/BridgeValidationHook.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

/// @notice Unit tests for BridgeValidationHook calldata extraction
contract BridgeValidationHookUnitTest is Test {
    TestHook hook;

    function setUp() public {
        hook = new TestHook();
    }

    /// @notice Test that uint16 extraction works correctly for various chain IDs
    function testExtractUint16FromCalldata() public {
        // Test with BASE_WORMHOLE_CHAIN_ID = 30 (0x001e)
        bytes memory calldata1 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x123),
            1000000 * 1e18,
            uint16(30) // BASE chain ID
        );

        uint16 extracted1 = hook.extractUint16FromCalldata(calldata1);
        assertEq(extracted1, 30, "Should extract chain ID 30");

        // Test with MOONBEAM_WORMHOLE_CHAIN_ID = 16 (0x0010)
        bytes memory calldata2 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x456),
            2000000 * 1e18,
            uint16(16) // Moonbeam chain ID
        );

        uint16 extracted2 = hook.extractUint16FromCalldata(calldata2);
        assertEq(extracted2, 16, "Should extract chain ID 16");

        // Test with ETHEREUM_WORMHOLE_CHAIN_ID = 2 (0x0002)
        bytes memory calldata3 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x789),
            3000000 * 1e18,
            uint16(2) // Ethereum chain ID
        );

        uint16 extracted3 = hook.extractUint16FromCalldata(calldata3);
        assertEq(extracted3, 2, "Should extract chain ID 2");

        // Test with max uint16 value
        bytes memory calldata4 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0xabc),
            4000000 * 1e18,
            type(uint16).max // 65535
        );

        uint16 extracted4 = hook.extractUint16FromCalldata(calldata4);
        assertEq(extracted4, type(uint16).max, "Should extract max uint16");

        // Test with zero
        bytes memory calldata5 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0xdef),
            5000000 * 1e18,
            uint16(0)
        );

        uint16 extracted5 = hook.extractUint16FromCalldata(calldata5);
        assertEq(extracted5, 0, "Should extract zero");
    }

    /// @notice Test calldata length validation
    function testExtractUint16RevertsOnShortCalldata() public {
        // Create calldata that's too short (only 50 bytes)
        bytes memory shortCalldata = new bytes(50);

        vm.expectRevert("BridgeValidationHook: invalid calldata length");
        hook.extractUint16FromCalldata(shortCalldata);
    }

    /// @notice Test with exact minimum length (100 bytes)
    function testExtractUint16WithExactLength() public {
        bytes memory calldata1 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x123),
            1000 * 1e18,
            uint16(30)
        );

        // Should be exactly 100 bytes: 4 (selector) + 32 (address) + 32 (uint256) + 32 (uint16)
        assertEq(calldata1.length, 100, "Calldata should be 100 bytes");

        uint16 extracted = hook.extractUint16FromCalldata(calldata1);
        assertEq(
            extracted,
            30,
            "Should extract chain ID from 100-byte calldata"
        );
    }

    /// @notice Test bytesToBytes4 function
    function testBytesToBytes4() public {
        bytes memory data = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x123),
            1000 * 1e18,
            uint16(30)
        );

        bytes4 selector = hook.bytesToBytes4(data);
        bytes4 expectedSelector = bytes4(
            keccak256("bridgeToRecipient(address,uint256,uint16)")
        );

        assertEq(selector, expectedSelector, "Should extract correct selector");
    }

    /// @notice Test bytesToBytes4 with short data
    function testBytesToBytes4WithShortData() public {
        bytes memory shortData = new bytes(2);
        bytes4 selector = hook.bytesToBytes4(shortData);
        assertEq(selector, bytes4(0), "Should return zero for short data");
    }

    /// @notice Fuzz test for extractUint16 with random values
    function testFuzzExtractUint16(uint16 chainId) public {
        bytes memory calldata1 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x123),
            1000000 * 1e18,
            chainId
        );

        uint16 extracted = hook.extractUint16FromCalldata(calldata1);
        assertEq(extracted, chainId, "Fuzz: Should extract any uint16 value");
    }

    /// @notice Test with different addresses and amounts (shouldn't affect uint16 extraction)
    function testExtractUint16WithVariedParameters(
        address recipient,
        uint256 amount,
        uint16 chainId
    ) public {
        vm.assume(amount < type(uint128).max); // Keep amounts reasonable

        bytes memory calldata1 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            recipient,
            amount,
            chainId
        );

        uint16 extracted = hook.extractUint16FromCalldata(calldata1);
        assertEq(
            extracted,
            chainId,
            "Chain ID extraction should be independent of other params"
        );
    }

    /// @notice Verify ABI encoding behavior and document the extraction logic
    function testABIEncodingBehavior() public view {
        // Create calldata with known chain ID
        bytes memory calldata1 = abi.encodeWithSignature(
            "bridgeToRecipient(address,uint256,uint16)",
            address(0x1234567890123456789012345678901234567890),
            uint256(1000000000000000000000000), // 1M tokens
            uint16(30) // BASE_WORMHOLE_CHAIN_ID = 0x001e
        );

        // Calldata structure (100 bytes total):
        // Bytes 0-3:   Function selector (4 bytes)
        // Bytes 4-35:  Address parameter (32 bytes, left-padded)
        // Bytes 36-67: uint256 parameter (32 bytes)
        // Bytes 68-99: uint16 parameter  (32 bytes, LEFT-padded with zeros)
        //
        // For uint16(30) = 0x001e:
        // ABI encoding stores it as: 0x000000000000000000000000000000000000000000000000000000000000001e
        //                             ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ zeros ^^^^^^  ^^value^^
        //                             (left-padded)                                (rightmost 2 bytes)
        //
        // Therefore, extracting the RIGHTMOST 2 bytes gives us the correct value.

        assertEq(calldata1.length, 100, "Total calldata should be 100 bytes");

        // The current implementation correctly extracts from the rightmost position
        console.log(
            "ABI encoding is LEFT-padded (zeros on left, value on right)"
        );
        console.log(
            "Current extraction: uint16(uint256(rawBytes)) takes RIGHTMOST 2 bytes"
        );
        console.log("This is CORRECT for left-padded ABI encoding");
    }

    /// @notice Test zero bridge cost allows only value=0
    function testZeroBridgeCostAllowsZeroValue() public {
        // Create a mock router that returns zero bridge cost
        MockZeroCostRouter mockRouter = new MockZeroCostRouter();

        // value=0 should pass when bridgeCost is 0
        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: address(mockRouter),
            value: 0,
            data: abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                address(0x123),
                1000 * 1e18,
                uint16(30)
            ),
            description: "Test bridge with zero cost router",
            actionType: ActionType.Moonbeam
        });

        // Should pass — 0 is within [0*4, 0*10] = [0, 0]
        hook.verifyBridgeActions(actions);
    }

    /// @notice Test zero bridge cost rejects non-zero value
    function testZeroBridgeCostRejectsNonZeroValue() public {
        MockZeroCostRouter mockRouter = new MockZeroCostRouter();

        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: address(mockRouter),
            value: 1,
            data: abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                address(0x123),
                1000 * 1e18,
                uint16(30)
            ),
            description: "Test bridge with zero cost router and non-zero value",
            actionType: ActionType.Moonbeam
        });

        // Should revert — 1 > 0*10 = 0
        vm.expectRevert();
        hook.verifyBridgeActions(actions);
    }

    /// @notice Test router validation with EOA
    function testRouterMustBeContract() public {
        // Use an EOA address
        address eoaRouter = address(0x1234567890123456789012345678901234567890);

        // Create proposal action with EOA router
        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: eoaRouter,
            value: 1 ether,
            data: abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                address(0x123),
                1000 * 1e18,
                uint16(30)
            ),
            description: "Test bridge with EOA router",
            actionType: ActionType.Moonbeam
        });

        // Should revert with router validation error
        vm.expectRevert("BridgeValidationHook: router must be a contract");
        hook.verifyBridgeActions(actions);
    }
}

/// @notice Test harness to expose internal functions
contract TestHook is BridgeValidationHook {
    // Expose _verifyBridgeActions for testing
    function verifyBridgeActions(
        ProposalAction[] memory proposal
    ) external view {
        _verifyBridgeActions(proposal);
    }

    // Implement bytesToBytes4 required by abstract parent
    function bytesToBytes4(
        bytes memory toSlice
    ) public pure override returns (bytes4 functionSignature) {
        if (toSlice.length < 4) {
            return bytes4(0);
        }

        assembly {
            functionSignature := mload(add(toSlice, 0x20))
        }
    }
}

/// @notice Mock router that returns zero bridge cost
contract MockZeroCostRouter {
    function bridgeCost(uint16) external pure returns (uint256) {
        return 0;
    }
}

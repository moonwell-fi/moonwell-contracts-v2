// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainIds, MOONBEAM_FORK_ID, BASE_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/// @notice Integration test for BridgeValidationHook using real forked contracts
contract BridgeValidationHookIntegrationTest is Test {
    using ChainIds for uint256;

    Addresses public addresses;
    xWELLRouter public router;
    WormholeBridgeAdapter public wormholeAdapter;
    uint256 public actualBridgeCost;

    function setUp() public {
        // Create Moonbeam fork
        vm.createSelectFork(vm.envString("MOONBEAM_RPC_URL"));

        // Initialize addresses
        addresses = new Addresses();

        // Get real deployed contracts
        router = xWELLRouter(addresses.getAddress("xWELL_ROUTER"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        // Query actual bridge cost from the real router.
        // After mip-x48 (FIND-002), bridgeCost returns messageFee() which
        // is currently 0 on all chains since the deprecated relayer quoter
        // was removed.
        actualBridgeCost = router.bridgeCost(BASE_WORMHOLE_CHAIN_ID);
    }

    /// ============ SUCCESS TESTS ============

    function testValidBridgeAtMinimum() public {
        ValidBridgeMinimumProposal proposal = new ValidBridgeMinimumProposal(
            actualBridgeCost
        );

        // This should pass validation
        proposal.build(addresses);

        // Verify the proposal was built correctly
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        assertEq(targets.length, 1, "Should have 1 action");
        assertEq(
            values[0],
            actualBridgeCost * 4,
            "Value should be 4x bridge cost"
        );
    }

    function testValidBridgeAtMaximum() public {
        ValidBridgeMaximumProposal proposal = new ValidBridgeMaximumProposal(
            actualBridgeCost
        );

        // This should pass validation
        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        assertEq(targets.length, 1, "Should have 1 action");
        assertEq(
            values[0],
            actualBridgeCost * 10,
            "Value should be 10x bridge cost"
        );
    }

    function testValidBridgeInRange() public {
        ValidBridgeProposal proposal = new ValidBridgeProposal(
            actualBridgeCost
        );

        // This should pass validation
        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        assertEq(targets.length, 1, "Should have 1 action");
        assertEq(
            values[0],
            actualBridgeCost * 7,
            "Value should be 7x bridge cost"
        );
    }

    function testMultipleBridgeCalls() public {
        MultipleBridgesProposal proposal = new MultipleBridgesProposal(
            actualBridgeCost
        );

        // This should pass validation
        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        assertEq(targets.length, 3, "Should have 3 actions");
        assertEq(values[0], actualBridgeCost * 6, "First value should be 6x");
        assertEq(values[1], actualBridgeCost * 7, "Second value should be 7x");
        assertEq(values[2], actualBridgeCost * 8, "Third value should be 8x");
    }

    /// ============ FAILURE TESTS ============

    function testFailInvalidBridgeTooLow() public {
        InvalidBridgeTooLowProposal proposal = new InvalidBridgeTooLowProposal(
            actualBridgeCost
        );

        // Calculate expected values for error message
        uint256 minValue = actualBridgeCost * 4;
        uint256 actualValue = actualBridgeCost * 3;

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too low. Expected >= ",
            vm.toString(minValue),
            ", got ",
            vm.toString(actualValue)
        );

        // This should fail validation with specific message
        vm.expectRevert(bytes(expectedError));
        proposal.build(addresses);
    }

    function testInvalidBridgeTooLowRevertMessage() public {
        /// Range validation is meaningless when bridgeCost is 0 (all multiples are 0)
        vm.skip(actualBridgeCost == 0);
        InvalidBridgeTooLowProposal proposal = new InvalidBridgeTooLowProposal(
            actualBridgeCost
        );

        // Build the proposal
        proposal.build(addresses);

        // Get the proposal actions
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        // Create ProposalAction array
        ProposalAction[] memory actions = new ProposalAction[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            actions[i] = ProposalAction({
                target: targets[i],
                value: values[i],
                data: calldatas[i],
                description: "",
                actionType: ActionType.Moonbeam
            });
        }

        // Calculate expected values for error message
        uint256 minValue = actualBridgeCost * 4;
        uint256 actualValue = actualBridgeCost * 3;

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too low. Expected >= ",
            vm.toString(minValue),
            ", got ",
            vm.toString(actualValue)
        );

        // Try to validate - should revert with specific message
        vm.expectRevert(bytes(expectedError));

        // This will trigger the hook validation
        proposal.testVerifyBridgeActions(actions);
    }

    function testFailInvalidBridgeTooHigh() public {
        InvalidBridgeTooHighProposal proposal = new InvalidBridgeTooHighProposal(
                actualBridgeCost
            );

        // Calculate expected values for error message
        uint256 maxValue = actualBridgeCost * 10;
        uint256 actualValue = actualBridgeCost * 11;

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too high. Expected <= ",
            vm.toString(maxValue),
            ", got ",
            vm.toString(actualValue)
        );

        // Build and expect revert during validation with specific message
        vm.expectRevert(bytes(expectedError));
        proposal.build(addresses);
    }

    function testInvalidBridgeTooHighRevertMessage() public {
        vm.skip(actualBridgeCost == 0);
        InvalidBridgeTooHighProposal proposal = new InvalidBridgeTooHighProposal(
                actualBridgeCost
            );

        // Build the proposal
        proposal.build(addresses);

        // Get the proposal actions
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        ProposalAction[] memory actions = new ProposalAction[](targets.length);
        for (uint256 i = 0; i < targets.length; i++) {
            actions[i] = ProposalAction({
                target: targets[i],
                value: values[i],
                data: calldatas[i],
                description: "",
                actionType: ActionType.Moonbeam
            });
        }

        // Calculate expected values for error message
        uint256 maxValue = actualBridgeCost * 10;
        uint256 actualValue = actualBridgeCost * 11;

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too high. Expected <= ",
            vm.toString(maxValue),
            ", got ",
            vm.toString(actualValue)
        );

        // Try to validate - should revert with specific message
        vm.expectRevert(bytes(expectedError));

        proposal.testVerifyBridgeActions(actions);
    }

    /// ============ EDGE CASE TESTS ============

    function testBoundaryConditionJustBelowMinimum() public {
        vm.skip(actualBridgeCost == 0);
        // Test with 3.99x (just below minimum)
        BoundaryBelowMinimumProposal proposal = new BoundaryBelowMinimumProposal(
                actualBridgeCost
            );

        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: targets[0],
            value: values[0],
            data: calldatas[0],
            description: "",
            actionType: ActionType.Moonbeam
        });

        // Calculate expected values for error message
        uint256 minValue = actualBridgeCost * 4;
        uint256 actualValue = (actualBridgeCost * 399) / 100; // 3.99x

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too low. Expected >= ",
            vm.toString(minValue),
            ", got ",
            vm.toString(actualValue)
        );

        // Should fail validation with specific message
        vm.expectRevert(bytes(expectedError));

        proposal.testVerifyBridgeActions(actions);
    }

    function testBoundaryConditionJustAboveMaximum() public {
        vm.skip(actualBridgeCost == 0);
        // Test with 10.01x (just above maximum)
        BoundaryAboveMaximumProposal proposal = new BoundaryAboveMaximumProposal(
                actualBridgeCost
            );

        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: targets[0],
            value: values[0],
            data: calldatas[0],
            description: "",
            actionType: ActionType.Moonbeam
        });

        // Calculate expected values for error message
        uint256 maxValue = actualBridgeCost * 10;
        uint256 actualValue = (actualBridgeCost * 1001) / 100; // 10.01x

        // Build expected error message
        string memory expectedError = string.concat(
            "BridgeValidationHook: bridge value too high. Expected <= ",
            vm.toString(maxValue),
            ", got ",
            vm.toString(actualValue)
        );

        // Should fail validation with specific message
        vm.expectRevert(bytes(expectedError));

        proposal.testVerifyBridgeActions(actions);
    }

    /// ============ VALIDATION TESTS ============

    function testInvalidRouterNotContract() public {
        InvalidRouterNotContractProposal proposal = new InvalidRouterNotContractProposal(
                actualBridgeCost
            );

        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            ,

        ) = proposal.getProposalActionSteps();

        ProposalAction[] memory actions = new ProposalAction[](1);
        actions[0] = ProposalAction({
            target: targets[0],
            value: values[0],
            data: calldatas[0],
            description: "",
            actionType: ActionType.Moonbeam
        });

        // Should fail validation - router is not a contract
        vm.expectRevert("BridgeValidationHook: router must be a contract");

        proposal.testVerifyBridgeActions(actions);
    }
}

/// ============ TEST PROPOSAL CONTRACTS ============

/// @notice Base contract for test proposals with helper functions
abstract contract BaseTestProposal is Configs, HybridProposal {
    using ChainIds for uint256;
    using ProposalActions for *;

    /// Test constants
    uint256 public constant TEST_BRIDGE_AMOUNT = 1_000_000 * 1e18;
    address public constant TEST_RECIPIENT = address(0x123456);

    uint256 public bridgeCost;

    constructor(uint256 _bridgeCost) {
        bridgeCost = _bridgeCost;
        bytes memory proposalDescription = abi.encodePacked(
            "Test proposal for BridgeValidationHook"
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    /// Helper function to expose _verifyBridgeActions for testing
    function testVerifyBridgeActions(
        ProposalAction[] memory proposal
    ) external view {
        _verifyBridgeActions(proposal);
    }

    /// Helper to create bridge action
    function createBridgeAction(
        Addresses addresses,
        uint256 value,
        uint256 amount
    ) internal {
        _pushAction(
            addresses.getAddress("xWELL_ROUTER"),
            value,
            abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                TEST_RECIPIENT, // recipient
                amount, // amount to bridge
                BASE_WORMHOLE_CHAIN_ID // destination chain
            ),
            "Bridge WELL to Base via xWELL Router",
            ActionType.Moonbeam
        );
    }

    function simulate(Addresses, address) public pure override {}

    function validate(Addresses, address) public pure override {}
}

/// @notice Valid proposal with bridge value at minimum (4x)
contract ValidBridgeMinimumProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "VALID_BRIDGE_MINIMUM";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            bridgeCost * 4, // 4x bridge cost (minimum)
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Valid proposal with bridge value at maximum (10x)
contract ValidBridgeMaximumProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "VALID_BRIDGE_MAXIMUM";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            bridgeCost * 10, // 10x bridge cost (maximum)
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Valid proposal with bridge value in range (7x)
contract ValidBridgeProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "VALID_BRIDGE_IN_RANGE";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            bridgeCost * 7, // 7x bridge cost (mid-range)
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Proposal with multiple valid bridge calls
contract MultipleBridgesProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "MULTIPLE_BRIDGES";

    function build(Addresses addresses) public override {
        createBridgeAction(addresses, bridgeCost * 6, TEST_BRIDGE_AMOUNT);
        createBridgeAction(addresses, bridgeCost * 7, TEST_BRIDGE_AMOUNT * 2);
        createBridgeAction(addresses, bridgeCost * 8, TEST_BRIDGE_AMOUNT * 3);
    }
}

/// @notice Invalid proposal - bridge value too low (3x)
contract InvalidBridgeTooLowProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "INVALID_BRIDGE_TOO_LOW";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            bridgeCost * 3, // 3x bridge cost (below minimum of 4x)
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Invalid proposal - bridge value too high (11x)
contract InvalidBridgeTooHighProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "INVALID_BRIDGE_TOO_HIGH";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            bridgeCost * 11, // 11x bridge cost (above maximum of 10x)
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Boundary test - just below minimum (3.99x)
contract BoundaryBelowMinimumProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "BOUNDARY_BELOW_MINIMUM";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            (bridgeCost * 399) / 100, // 3.99x bridge cost
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Boundary test - just above maximum (10.01x)
contract BoundaryAboveMaximumProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "BOUNDARY_ABOVE_MAXIMUM";

    function build(Addresses addresses) public override {
        createBridgeAction(
            addresses,
            (bridgeCost * 1001) / 100, // 10.01x bridge cost
            TEST_BRIDGE_AMOUNT
        );
    }
}

/// @notice Invalid proposal - router is not a contract (EOA address)
contract InvalidRouterNotContractProposal is BaseTestProposal {
    constructor(uint256 _bridgeCost) BaseTestProposal(_bridgeCost) {}

    string public constant override name = "INVALID_ROUTER_NOT_CONTRACT";

    function build(Addresses) public override {
        // Use an EOA address instead of a contract
        address eoaRouter = address(0x1234567890123456789012345678901234567890);

        _pushAction(
            eoaRouter, // EOA instead of contract
            bridgeCost * 7,
            abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                TEST_RECIPIENT,
                TEST_BRIDGE_AMOUNT,
                BASE_WORMHOLE_CHAIN_ID
            ),
            "Bridge WELL to Base via invalid router",
            ActionType.Moonbeam
        );
    }
}

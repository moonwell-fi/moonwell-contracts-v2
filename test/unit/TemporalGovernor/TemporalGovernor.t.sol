pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITemporalGovernor, TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {AddressUtils} from "@utils/AddressUtils.sol";

interface InstrumentedExternalEvents {
    /// @notice Emitted when a VAA is decoded
    event DecodedVAA(
        address intendedRecipient,
        address[] targets,
        uint[] values,
        string[] signatures,
        bytes[] calldatas
    );

    /// @notice Emitted when a transaction is executed
    event ExecutedTransaction(
        address target,
        uint value,
        string signature,
        bytes data
    );

    /// @notice emitted when guardian pause is granted
    event GuardianPauseGranted(uint256 indexed timestamp);

    /// @notice Emitted when a trusted sender is updated
    event TrustedSenderUpdated(uint16 chainId, address addr);
}

contract TemporalGovernorUnitTest is Test, InstrumentedExternalEvents {
    using SafeCast for *;
    using AddressUtils for address;

    TemporalGovernor governor;
    address public constant admin = address(100);
    address public constant wormholeCore = address(100_000_000);

    /// @notice proposal delay time
    uint256 public constant proposalDelay = 1 days;

    /// @notice time before anyone can unpause the contract after a guardian pause
    uint256 public constant permissionlessUnpauseTime = 30 days;

    function setUp() public {
        TemporalGovernor.TrustedSender[]
            memory trustedSenders = new TemporalGovernor.TrustedSender[](1);
        trustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: block.chainid.toUint16(),
            addr: admin
        });
        governor = new TemporalGovernor(
            wormholeCore,
            proposalDelay,
            permissionlessUnpauseTime,
            trustedSenders
        );
    }

    function testSetupCorrectly() public {
        assertTrue(
            governor.isTrustedSender(
                block.chainid.toUint16(),
                governor.toBytes(admin)
            )
        );
        assertEq(address(governor.wormholeBridge()), wormholeCore);
    }

    function testCannotsetTrustedSendersNonTemporalGovernor() public {
        TemporalGovernor.TrustedSender[]
            memory trustedSenders = new TemporalGovernor.TrustedSender[](1);

        vm.expectRevert(
            "TemporalGovernor: Only this contract can update trusted senders"
        );
        governor.setTrustedSenders(trustedSenders);
    }

    function testQueueProposalFailsPaused() public {
        governor.togglePause();
        assertTrue(governor.paused());

        vm.expectRevert("Pausable: paused");
        governor.queueProposal("");
    }

    function testExecuteProposalFailsPaused() public {
        governor.togglePause();
        assertTrue(governor.paused());

        vm.expectRevert("Pausable: paused");
        governor.executeProposal("");
    }

    function testUnpauseSucceeds() public {
        governor.togglePause();
        assertTrue(governor.paused());
        assertEq(governor.lastPauseTime(), block.timestamp);
        assertFalse(governor.guardianPauseAllowed());

        governor.togglePause();
        assertFalse(governor.paused());
    }

    function testProcessRequestNonGuardian() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(admin);
        governor.fastTrackProposalExecution("");
    }

    function testTogglePauseFailsNonOwner() public {
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(admin);
        governor.togglePause();
    }

    function testsetTrustedSendersAsTemporalGovernorSucceeds() public {
        address newAdmin = address(100_000_001);
        TemporalGovernor.TrustedSender[]
            memory trustedSenders = new TemporalGovernor.TrustedSender[](1);
        trustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: block.chainid.toUint16(),
            addr: newAdmin
        });

        vm.prank(address(governor));
        governor.setTrustedSenders(trustedSenders);

        assertTrue(
            governor.isTrustedSender(
                block.chainid.toUint16(),
                governor.addressToBytes(newAdmin)
            )
        );
        assertTrue(
            governor.isTrustedSender(
                block.chainid.toUint16(),
                governor.addressToBytes(admin)
            )
        );
    }

    function testUnsetTrustedSendersAsTemporalGovernorSucceeds() public {
        address newAdmin = address(100_000_001);
        TemporalGovernor.TrustedSender[]
            memory trustedSenders = new TemporalGovernor.TrustedSender[](1);
        trustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: block.chainid.toUint16(),
            addr: newAdmin
        });

        vm.prank(address(governor));
        governor.unSetTrustedSenders(trustedSenders);

        assertFalse(
            governor.isTrustedSender(
                block.chainid.toUint16(),
                governor.addressToBytes(newAdmin)
            )
        );
        assertTrue(
            governor.isTrustedSender(
                block.chainid.toUint16(),
                governor.addressToBytes(admin)
            )
        );
    }

    function testUnsetTrustedSendersNotAsTemporalGovernorFails() public {
        TemporalGovernor.TrustedSender[]
            memory trustedSenders = new TemporalGovernor.TrustedSender[](1);

        vm.expectRevert(
            "TemporalGovernor: Only this contract can update trusted senders"
        );
        governor.unSetTrustedSenders(trustedSenders);
    }

    function testGrantGuardiansPauseNotTemporalGovernorFails() public {
        vm.expectRevert(
            "TemporalGovernor: Only this contract can update grant guardian pause"
        );
        governor.grantGuardiansPause();
    }

    function testGrantGuardiansPauseTemporalGovernorSucceeds() public {
        governor.togglePause();
        assertTrue(governor.paused());
        assertFalse(governor.guardianPauseAllowed());

        vm.expectEmit(true, true, true, true, address(governor));
        emit GuardianPauseGranted(block.timestamp);

        vm.prank(address(governor));
        governor.grantGuardiansPause();

        assertTrue(governor.guardianPauseAllowed());
    }

    function testRevokeGuardianUnpausedSucceedsAsGuardian() public {
        governor.revokeGuardian();

        _postRevokeAssertions();
    }

    function testRevokeGuardianPausedSucceedsAsGuardian() public {
        governor.togglePause();
        assertTrue(governor.paused());

        governor.revokeGuardian();

        _postRevokeAssertions();
    }

    function testRevokeGuardianUnpausedSucceedsAsTemporalGovernor() public {
        assertFalse(governor.paused());

        vm.prank(address(governor));
        governor.revokeGuardian();

        _postRevokeAssertions();
    }

    function testRevokeGuardianPausedSucceedsAsTemporalGovernor() public {
        governor.togglePause();
        assertTrue(governor.paused());

        vm.prank(address(governor));
        governor.revokeGuardian();

        _postRevokeAssertions();
    }

    function testRevokeGuardianAsNonGuardianOrGovernorFails() public {
        vm.prank(admin);
        vm.expectRevert("TemporalGovernor: cannot revoke guardian");
        governor.revokeGuardian();
    }

    function testChangeGuardianAsNonGovernorFails() public {
        vm.prank(admin);
        vm.expectRevert("TemporalGovernor: cannot change guardian");
        governor.changeGuardian(address(1));
    }

    function testChangeGuardianAsGovernorSucceeds() public {
        address newGuardian = address(1);

        vm.prank(address(governor));
        governor.changeGuardian(newGuardian);

        assertEq(newGuardian, governor.owner());
    }

    function testPermissionlessUnpauseSucceedsAfterWaitTime() public {
        governor.togglePause();
        assertTrue(governor.paused());

        vm.warp(block.timestamp + governor.permissionlessUnpauseTime());

        governor.permissionlessUnpause();
        assertEq(governor.lastPauseTime(), 0);
        assertFalse(governor.paused());
    }

    function testPermissionlessUnpauseFailsBeforeWaitTimeFinished() public {
        governor.togglePause();
        assertTrue(governor.paused());
        vm.expectRevert("TemporalGovernor: not past pause window");
        governor.permissionlessUnpause();
    }

    function testPermissionlessUnpauseFailsWhenUnpaused() public {
        vm.expectRevert("Pausable: not paused");
        governor.permissionlessUnpause();
    }

    function testGuardianCannotRepause() public {
        governor.togglePause();
        assertTrue(governor.paused());
        assertFalse(governor.guardianPauseAllowed());
        assertEq(governor.lastPauseTime(), block.timestamp);

        governor.togglePause();
        assertFalse(governor.paused());
        assertFalse(governor.guardianPauseAllowed());
        assertEq(governor.lastPauseTime(), block.timestamp);

        vm.expectRevert("TemporalGovernor: guardian pause not allowed");
        governor.togglePause();
    }

    function _postRevokeAssertions() private {
        assertFalse(governor.paused());
        assertEq(governor.lastPauseTime(), 0);
        assertEq(governor.owner(), address(0));
        assertFalse(governor.guardianPauseAllowed());
    }
}

pragma solidity 0.8.19;

import {ConfigurablePause} from "@protocol/xWELL/ConfigurablePause.sol";

/// @notice possible states for this contract to be in:
///     1. paused, pauseStartTime != 0, guardian != address(0)
///     2. unpaused, pauseStartTime == 0, guardian == address(0)
///     3. unpaused, pauseStartTime <= block.timestamp - pauseDuration, guardian != address(0)
///     4. unpaused after kick, pauseStartTime == 0, guardian == address(0)
contract ConfigurablePauseGuardian is ConfigurablePause {
    /// @notice address of the pause guardian
    address public pauseGuardian;

    /// @notice emitted when the pause guardian is updated
    /// @param oldPauseGuardian old pause guardian
    /// @param newPauseGuardian new pause guardian
    event PauseGuardianUpdated(
        address indexed oldPauseGuardian, address indexed newPauseGuardian
    );

    /// @notice returns whether the pause has been used by the pause guardian
    /// if pauseStartTime is 0, contract pause is not used, if non zero, it is used
    function pauseUsed() public view returns (bool) {
        return pauseStartTime != 0;
    }

    /// @notice kick the guardian, can only kick while the contracts are not paused
    /// only callably if a pause guardian pauses, then fails to unpause before
    /// the pauseDuration lapses
    /// removes the guardian, sets pause time to 0, and resets the pauseUsed flag to false
    function kickGuardian() public whenNotPaused {
        require(
            pauseUsed(),
            "ConfigurablePauseGuardian: did not pause, so cannot kick"
        );

        _resetPauseState();
    }

    /// @notice helper function that:
    /// 1). kicks the current guardian
    /// 2). sets pauseUsed to false
    /// 3). unpauses the contracts by setting pause time to 0
    function _resetPauseState() private {
        address previousPauseGuardian = pauseGuardian;

        pauseGuardian = address(0);

        /// remove the pause guardian

        _setPauseTime(0);

        /// fully unpause, set pauseStartTime to 0

        emit PauseGuardianUpdated(previousPauseGuardian, address(0));
    }

    /// @notice pause the contracts, can only pause while the contracts are unpaused
    /// uses up the pause, and starts the pause timer
    function pause() public virtual whenNotPaused {
        require(
            msg.sender == pauseGuardian,
            "ConfigurablePauseGuardian: only pause guardian"
        );
        require(!pauseUsed(), "ConfigurablePauseGuardian: pause already used");

        /// pause, set pauseStartTime to current block timestamp
        _setPauseTime(uint128(block.timestamp));

        emit Paused(msg.sender);
    }

    /// @notice unpause the contracts as pause guardian.
    /// revokes pause guardian role after unpausing
    function unpause() external whenPaused {
        require(
            msg.sender == pauseGuardian,
            "ConfigurablePauseGuardian: only pause guardian"
        );

        /// kick the guardian
        /// set pauseUsed to false
        /// unpause the contracts by setting pause time to 0
        _resetPauseState();

        emit Unpaused(msg.sender);
    }

    /// @dev when a new guardian is granted, the contract is automatically unpaused
    /// @notice grant pause guardian role to a new address
    /// this should be done after the previous pause guardian has been kicked,
    /// however there are no checks on this as only the owner will call this function
    /// and the owner is assumed to be non-malicious
    function _grantGuardian(address newPauseGuardian) internal {
        address previousPauseGuardian = pauseGuardian;
        pauseGuardian = newPauseGuardian;

        /// if a new guardian is granted, the contract is automatically unpaused
        _setPauseTime(0);

        emit PauseGuardianUpdated(previousPauseGuardian, newPauseGuardian);
    }
}

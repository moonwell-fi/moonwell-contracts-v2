pragma solidity 0.8.19;

import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";

contract ConfigurablePause is PausableUpgradeable {
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice pause start time, starts at 0 so contract is unpaused
    uint128 public pauseStartTime;

    /// @notice pause duration
    uint128 public pauseDuration;

    /// @notice event emitted when pause start time is updated
    event PauseTimeUpdated(
        uint256 indexed newPauseStartTime,
        uint256 indexed newPauseDuration
    );

    event PauseDurationUpdated(
        uint256 indexed newPauseStartTime,
        uint256 indexed newPauseDuration
    );

    /// @notice return the current pause status
    /// if pauseStartTime is 0, contract is not paused
    /// if pauseStartTime is not 0, contract could be paused in the pauseDuration window
    function paused() public view virtual override returns (bool) {
        return
            pauseStartTime == 0
                ? false
                : block.timestamp <= pauseStartTime + pauseDuration;
    }

    /// @notice can only start a pause if the contract is not already paused
    function _startPause() internal virtual whenNotPaused {
        _setPauseTime(uint128(block.timestamp));
    }

    /// @notice can only end a pause if the contract is already paused
    function _endPause() internal virtual whenPaused {
        _setPauseTime(uint128(block.timestamp));
    }

    function _updatePauseDuration(uint128 newPauseDuration) internal virtual {
        pauseDuration = newPauseDuration;

        emit PauseDurationUpdated(block.timestamp, pauseDuration);
    }

    function _setPauseTime(uint128 newPauseStartTime) internal {
        pauseStartTime = newPauseStartTime;

        emit PauseTimeUpdated(newPauseStartTime, pauseDuration);
    }
}

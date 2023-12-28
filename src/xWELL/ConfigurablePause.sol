pragma solidity 0.8.19;

import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";

/// @notice pause contract that has a duration for each pause period.
/// This contract has a pause duration and a pause start time.
/// Invariants:
///  - When the pause start time is non zero, the contract is able to return paused as true.
///  - Once the block timestamp is greater than the pause start time + pause duration, the
///  contract is automatically unpaused.
///  - Block timestamp gte pause start time && block timestamp lte pause start time + pause
///  duration, then the contract is paused
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
    /// @param newPauseStartTime new pause start time
    event PauseTimeUpdated(uint256 indexed newPauseStartTime);

    /// @notice event emitted when pause duration is updated
    /// @param oldPauseDuration old pause duration
    /// @param newPauseDuration new pause duration
    event PauseDurationUpdated(
        uint256 oldPauseDuration,
        uint256 newPauseDuration
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

    /// ------------- INTERNAL HELPERS -------------

    /// @notice helper function to update the pause duration once the contract is paused
    /// @param newPauseDuration new pause duration
    function _updatePauseDuration(uint128 newPauseDuration) internal virtual {
        uint256 oldPauseDuration = pauseDuration;
        pauseDuration = newPauseDuration;

        emit PauseDurationUpdated(oldPauseDuration, pauseDuration);
    }

    /// @notice helper function to update the pause start time. used to pause the contract
    /// @param newPauseStartTime new pause start time
    function _setPauseTime(uint128 newPauseStartTime) internal {
        pauseStartTime = newPauseStartTime;

        emit PauseTimeUpdated(newPauseStartTime);
    }
}

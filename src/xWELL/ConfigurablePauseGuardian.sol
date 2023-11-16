pragma solidity 0.8.19;

import {PausableUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/security/PausableUpgradeable.sol";

import {ConfigurablePause} from "@protocol/xWELL/ConfigurablePause.sol";

contract ConfigurablePauseGuardian is ConfigurablePause {
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// ------------------ SINGLE STORAGE SLOT ------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice address of the pause guardian
    address public pauseGuardian;

    /// @notice whether or not the guardian has paused
    bool public pauseUsed;

    /// @notice emitted when the pause guardian is updated
    event PauseGuardianUpdated(
        address indexed oldPauseGuardian,
        address indexed newPauseGuardian
    );

    /// @notice initializer function for the ConfigurablePauseGuardian contract
    /// @param newPauseDuration the new pause duration
    /// @param newPauseGuardian the new pause guardian
    function __ConfigurablePauseGuardian_init(
        uint128 newPauseDuration,
        address newPauseGuardian
    ) internal onlyInitializing {
        __ConfigurablePause_init(newPauseDuration);

        pauseGuardian = newPauseGuardian;

        emit PauseGuardianUpdated(address(0), newPauseGuardian);
    }

    /// @notice kick the guardian, can only kick while the contracts are not paused
    /// removes the guardian, and resets the pauseUsed flag to false
    function kickGuardian() public whenNotPaused {
        require(
            pauseStartTime != 0,
            "ConfigurablePauseGuardian: did not pause, so cannot kick"
        );

        address previousPauseGuardian = pauseGuardian;

        pauseGuardian = address(0); /// remove the pause guardian
        pauseUsed = false; /// reset pauseUsed to false

        _setPauseTime(0); /// fully unpause, set pauseStartTime to 0

        emit PauseGuardianUpdated(previousPauseGuardian, address(0));
    }

    /// @notice pause the contracts, can only pause while the contracts are unpaused
    /// uses up the pause, and starts the pause timer
    function pause() external whenNotPaused {
        require(
            msg.sender == pauseGuardian,
            "ConfigurablePauseGuardian: only pause guardian"
        );
        require(!pauseUsed, "ConfigurablePauseGuardian: pause already used");

        pauseUsed = true;
        _startPause();

        emit Paused(msg.sender);
    }

    /// @notice unpause the contracts as pause guardian.
    /// revokes pause guardian role after unpausing
    function unpause() external whenPaused {
        require(
            msg.sender == pauseGuardian,
            "ConfigurablePauseGuardian: only pause guardian"
        );

        _endPause(); /// unpause the contracts
        kickGuardian(); /// kick the guardian

        emit Unpaused(msg.sender);
    }

    /// @notice grant pause guardian role to a new address
    /// this should be done after the previous pause guardian has been kicked,
    /// however there are no checks on this as only the owner will call this function
    /// and the owner is assumed to be non-malicious
    function _grantGuardian(address newPauseGuardian) internal {
        address previousPauseGuardian = newPauseGuardian;
        pauseUsed = false;
        pauseGuardian = newPauseGuardian;

        emit PauseGuardianUpdated(previousPauseGuardian, newPauseGuardian);
    }
}

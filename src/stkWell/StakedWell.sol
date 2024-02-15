// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./IERC20.sol";
import {StakedToken} from "./StakedToken.sol";

/**
 * @title StakedWell
 * @notice StakedToken with WELL token as staked token
 * @author Moonwell
 **/
contract StakedWell is StakedToken {
    string internal constant NAME = "Staked WELL";
    string internal constant SYMBOL = "stkWELL";
    uint8 internal constant DECIMALS = 18;

    /// @notice emitted when the cooldown seconds are updated
    event CooldownSecondsUpdated(uint256 newCooldownSeconds);

    /// @notice emitted when the unstake window is updated
    event UnstakeWindowUpdated(uint256 newUnstakeWindow);

    constructor() public initializer {}

    modifier onlyEmissionsManager() {
        require(
            msg.sender == EMISSION_MANAGER,
            "Only emissions manager can call this function"
        );
        _;
    }

    /**
     * @dev Called by the proxy contract
     **/
    function initialize(
        IERC20 stakedToken,
        IERC20 rewardToken,
        uint256 cooldownSeconds,
        uint256 unstakeWindow,
        address rewardsVault,
        address emissionManager,
        uint128 distributionDuration,
        address governance
    ) external {
        __StakedToken_init(
            stakedToken,
            rewardToken,
            cooldownSeconds,
            unstakeWindow,
            rewardsVault,
            emissionManager,
            distributionDuration,
            NAME,
            SYMBOL,
            DECIMALS,
            governance
        );
    }

    /// @notice update the cooldown seconds
    /// @param cooldownSeconds the new cooldown seconds
    function setCoolDownSeconds(
        uint256 cooldownSeconds
    ) external onlyEmissionsManager {
        COOLDOWN_SECONDS = cooldownSeconds;

        emit CooldownSecondsUpdated(cooldownSeconds);
    }

    /// @notice update the unstake window
    /// @param unstakeWindow the new unstake window
    function setUnstakeWindow(
        uint256 unstakeWindow
    ) external onlyEmissionsManager {
        UNSTAKE_WINDOW = unstakeWindow;

        emit UnstakeWindowUpdated(unstakeWindow);
    }
}

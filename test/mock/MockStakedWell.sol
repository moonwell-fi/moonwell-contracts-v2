// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

import {IERC20} from "@protocol/stkWell/IERC20.sol";
import {MockStakedToken} from "@test/mock/MockStakedToken.sol";

/// NOT TO BE USED IN PRODUCTION
/// FOR TESTING PURPOSES ONLY

/**
 * @title MockStakedWell with block numbers instead of timestamps
 * @notice StakedToken with WELL token as staked token
 * @author Moonwell
 *
 */
contract MockStakedWell is MockStakedToken {
    string internal constant NAME = "Staked WELL";
    string internal constant SYMBOL = "stkWELL";
    uint8 internal constant DECIMALS = 18;

    constructor() public initializer {}

    /**
     * @dev Called by the proxy contract
     *
     */
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
}

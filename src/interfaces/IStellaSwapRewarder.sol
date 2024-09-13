//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IStellaSwapRewarder {
    function poolRewardsPerSec(uint256 _pid) external view returns (uint256);

    function currentEndTimestamp(uint256 _pid) external view returns (uint256);
}

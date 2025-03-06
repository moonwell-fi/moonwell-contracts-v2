// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {IMultiRewards} from "crv-rewards/IMultiRewards.sol";

contract MultiRewardsDeploy is Test {
    function deployMultiRewards(
        address owner,
        address stakingToken
    ) public returns (address multiRewards) {
        multiRewards = deployCode(
            "artifacts/foundry/MultiRewards.sol/MultiRewards.json",
            abi.encode(owner, stakingToken)
        );
    }

    function validateMultiRewards(
        address multiRewards,
        address expectedOwner,
        address expectedStakingToken
    ) public view {
        IMultiRewards rewards = IMultiRewards(multiRewards);
        assertEq(rewards.owner(), expectedOwner, "Owner not set correctly");
        assertEq(
            address(rewards.stakingToken()),
            expectedStakingToken,
            "Staking token not set correctly"
        );
    }
}

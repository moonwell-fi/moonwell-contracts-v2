// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultiRewardsDeploy} from "src/rewards/MultiRewardsDeploy.sol";

/// test commands:
///
///      forge script DeployMultiRewards -vvv --fork-url base
///
///      forge script DeployMultiRewards -vvv --fork-url optimism
///
contract DeployMultiRewards is Script, MultiRewardsDeploy {
    function run() public {
        Addresses addresses = new Addresses();

        address owner = addresses.getAddress("TEMPORAL_GOVERNOR");
        address stakingToken = addresses.getAddress("USDC_METAMORPHO_VAULT");

        vm.startBroadcast();

        address multiRewards = deployMultiRewards(owner, stakingToken);
        validateMultiRewards(multiRewards, owner, stakingToken);

        vm.stopBroadcast();

        addresses.addAddress("MULTI_REWARDS", multiRewards);
        addresses.printAddresses();
    }
}

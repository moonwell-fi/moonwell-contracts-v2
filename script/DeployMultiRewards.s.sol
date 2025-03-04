// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {IMultiRewards} from "crv-rewards/IMultiRewards.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// test commands:
///
///      forge script DeployMultiRewards -vvv --fork-url base
///
///      forge script DeployMultiRewards -vvv --fork-url optimism
///
contract DeployMultiRewards is Script {
    function run() public {
        Addresses addresses = new Addresses();

        address owner = addresses.getAddress("TEMPORAL_GOVERNOR");
        address stakingToken = addresses.getAddress("USDC_METAMORPHO_VAULT");

        vm.startBroadcast();

        address multiRewards = deployCode(
            "artifacts/foundry/MultiRewards.sol/MultiRewards.json",
            abi.encode(owner, stakingToken)
        );

        // Verify owner and stakingToken are set correctly
        IMultiRewards rewards = IMultiRewards(multiRewards);
        require(rewards.owner() == owner, "Owner not set correctly");
        require(
            address(rewards.stakingToken()) == stakingToken,
            "Staking token not set correctly"
        );

        vm.stopBroadcast();

        addresses.addAddress("MULTI_REWARDS", multiRewards);
        addresses.printAddresses();
    }
}

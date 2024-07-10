// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";

/*
How to use:
forge script src/proposals/DeployJRM.s.sol:DeployJRM \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployJRM is Script {
    // baseRatePerYear: BigNumber { value: "10000000000000000" },
    // multiplierPerYear: BigNumber { value: "40000000000000000" },
    // jumpMultiplierPerYear: BigNumber { value: "3800000000000000000" },
    // kink: BigNumber { value: "750000000000000000" }

    uint256 public constant BASE_RATE_PER_YEAR = 10000000000000000;
    uint256 public constant MULTIPLIER_PER_YEAR = 40000000000000000;
    uint256 public constant JUMP_MULTIPLIER_PER_YEAR = 3800000000000000000;
    uint256 public constant KINK = 750000000000000000;

    function run() public {
        vm.startBroadcast();
        JumpRateModel jrm = new JumpRateModel(BASE_RATE_PER_YEAR, MULTIPLIER_PER_YEAR, JUMP_MULTIPLIER_PER_YEAR, KINK);

        vm.stopBroadcast();

        console.log("successfully deployed jrm: %d", address(jrm));
    }
}

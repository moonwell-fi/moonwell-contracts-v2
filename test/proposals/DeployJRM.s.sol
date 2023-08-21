// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mipb00 as mip} from "@test/proposals/mips/mip-b00/mip-b00.sol";

import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Well} from "@protocol/Governance/deprecated/Well.sol";

import {JumpRateModel} from "@protocol/IRModels/JumpRateModel.sol";

/*
How to use:
forge script test/proposals/DeployJRM.s.sol:DeployJRM \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployJRM is Script {
    uint256 public PRIVATE_KEY;

    // baseRatePerYear: BigNumber { value: "10000000000000000" },
    // multiplierPerYear: BigNumber { value: "40000000000000000" },
    // jumpMultiplierPerYear: BigNumber { value: "3800000000000000000" },
    // kink: BigNumber { value: "750000000000000000" }

    uint256 public constant BASE_RATE_PER_YEAR = 10000000000000000;
    uint256 public constant MULTIPLIER_PER_YEAR = 40000000000000000;
    uint256 public constant JUMP_MULTIPLIER_PER_YEAR = 3800000000000000000;
    uint256 public constant KINK = 750000000000000000;

    function setUp() public {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        vm.startBroadcast(PRIVATE_KEY);
        JumpRateModel jrm = new JumpRateModel(
            BASE_RATE_PER_YEAR,
            MULTIPLIER_PER_YEAR,
            JUMP_MULTIPLIER_PER_YEAR,
            KINK
        );

        console.log("successfully deployed jrm: %d", address(jrm));

        vm.stopBroadcast();
    }
}

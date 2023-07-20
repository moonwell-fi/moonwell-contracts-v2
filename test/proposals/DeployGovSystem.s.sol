// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mip00 as mip} from "@test/proposals/mips/mip00.sol";

import {MoonwellGovernorArtemis} from "@protocol/core/Governance/deprecated/MoonwellArtemisGovernor.sol";
import {Timelock} from "@protocol/core/Governance/deprecated/Timelock.sol";
import {Well} from "@protocol/core/Governance/deprecated/Well.sol";

/*
How to use:
forge script test/proposals/DeployGovSystem.s.sol:DeployGovSystem \
    -vvvv \
    --rpc-url moonbase \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployGovSystem is Script, mip {
    uint256 public PRIVATE_KEY;

    function setUp() public {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);
        Well well = new Well(deployerAddress);
        Timelock timelock = new Timelock(deployerAddress, 1 minutes);
        // DISTRIBUTOR = new address(0xe7E6cdb90797f053229c0A81C3De9dC8110188b5); // Moonbase Distributor
        // SAFETY_MODULE = new address(0x11fD9c97B0B8F50f6EB0e68342e3de8F76dd45fc); // Moonbase SM
        MoonwellGovernorArtemis governor = new MoonwellGovernorArtemis(
            address(timelock), // timelock
            address(well), // gov token (for voting power)
            0xe7E6cdb90797f053229c0A81C3De9dC8110188b5, // Moonbase distributor (for voting power)
            0x11fD9c97B0B8F50f6EB0e68342e3de8F76dd45fc, // Moonbase safety module (for voting power)
            address(deployerAddress), // break glass guardian
            address(deployerAddress), // governance return address
            address(deployerAddress), // governance return guardian
            1 days // guardian sunset
        );

        timelock.setPendingAdmin(address(governor));
        well.delegate(deployerAddress);

        vm.stopBroadcast();
    }
}

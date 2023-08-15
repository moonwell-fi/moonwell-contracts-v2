// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mip00 as mip} from "@test/proposals/mips/mip-00/mip-00.sol";

/*
How to use:
forge script test/proposals/DeployProposal.s.sol:DeployProposal \
    -vvvv \
    --rpc-url $ETH_RPC_URL \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployProposal is Script, mip {
    uint256 public PRIVATE_KEY;
    bool public DO_DEPLOY;
    bool public DO_AFTERDEPLOY;
    bool public DO_TEARDOWN;

    function setUp() public {
        // Default behavior: do debug prints
        DEBUG = vm.envOr("DEBUG", true);
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
        // Default behavior: do deploy
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        // Default behavior: do after-deploy
        DO_AFTERDEPLOY = vm.envOr("DO_AFTERDEPLOY", true);
        // Default behavior: don't do teardown
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", false);
    }

    function run() public {
        Addresses addresses = new Addresses();
        addresses.resetRecordingAddresses();
        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);
        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTERDEPLOY) afterDeploy(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        vm.stopBroadcast();

        if (DO_DEPLOY) {
            (
                string[] memory recordedNames,
                address[] memory recordedAddresses
            ) = addresses.getRecordedAddresses();
            for (uint256 i = 0; i < recordedNames.length; i++) {
                console.log("Deployed", recordedAddresses[i], recordedNames[i]);
            }

            console.log();

            for (uint256 i = 0; i < recordedNames.length; i++) {
                console.log('_addAddress("%s",',recordedNames[i]);
                console.log(block.chainid);
                console.log(", ");
                console.log(recordedAddresses[i]);
                console.log(");");
            }
        }
    }
}

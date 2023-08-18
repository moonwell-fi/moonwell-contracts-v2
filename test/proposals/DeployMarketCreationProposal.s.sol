// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mip0x as mip} from "@test/proposals/mips/examples/mip-market-listing.sol";

/*
How to use:
forge script test/proposals/DeployMarketCreationProposal.s.sol:DeployMarketCreationProposal \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.

to verify after deploy:
  forge verify-contract --etherscan-api-key $BASESCAN_API_KEY \ 
        <deployed contract address> src/MErc20Delegator.sol:MErc20Delegator
        --chain 8453

*/

contract DeployMarketCreationProposal is Script, mip {
    uint256 public PRIVATE_KEY;
    bool public DO_DEPLOY;
    bool public DO_AFTERDEPLOY;
    bool public DO_TEARDOWN;
    Addresses addresses;

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

        addresses = new Addresses();
        addresses.resetRecordingAddresses();
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        console.log("deployerAddress: ", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);

        deploy(addresses, deployerAddress);
        afterDeploy(addresses, deployerAddress);

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
                console.log('_addAddress("%s",', recordedNames[i]);
                console.log(block.chainid);
                console.log(", ");
                console.log(recordedAddresses[i]);
                console.log(");");
            }
        }
    }
}

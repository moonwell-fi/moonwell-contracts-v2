// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {mipb00 as mip} from "@test/proposals/mips/mip-b00/mip-b00.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";

/*
How to use:
1. set data to be signed VAA without prepended 0x
2. forge script test/proposals/ExecuteTemporalGovernor.s.sol:ExecuteTemporalGovernor \
    -vvvv \
    --rpc-url $ETH_RPC_URL \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract ExecuteTemporalGovernor is Script, mip {
    uint256 public PRIVATE_KEY;
    Addresses addresses;
    bytes constant data = hex"";

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address senderAddress = vm.addr(PRIVATE_KEY);
        console.log("sender address: ", senderAddress);

        TemporalGovernor gov = TemporalGovernor(addresses.getAddress("TEMPORAL_GOVERNOR"));
        vm.startBroadcast(PRIVATE_KEY);
        gov.executeProposal(data);
        vm.stopBroadcast();
    }
}

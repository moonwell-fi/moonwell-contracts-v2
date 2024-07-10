// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";

import {Addresses} from "@proposals/Addresses.sol";

function printAddresses(Addresses addresses) view {
    (
        string[] memory recordedNames,
        ,
        address[] memory recordedAddresses
    ) = addresses.getRecordedAddresses();
    for (uint256 j = 0; j < recordedNames.length; j++) {
        console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
        console.log("        'chainId': %d,", block.chainid);
        console.log(
            "        'name': '%s'\n}%s",
            recordedNames[j],
            j < recordedNames.length - 1 ? "," : ""
        );
    }
}

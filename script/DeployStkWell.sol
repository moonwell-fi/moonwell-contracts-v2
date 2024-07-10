// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";

// forge script script/DeployStkWell.sol --rpc-url moonbase -vvvv --broadcast -g 200 --slow
contract DeployStkWell is Script, MultichainGovernorDeploy {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        address well = addresses.getAddress("GOVTOKEN");

        vm.startBroadcast();

        (address ecosystemReserveProxy, address ecosystemReserveImplementation, address ecosystemReserveController) =
            deployEcosystemReserve(proxyAdmin);

        /// to mock the system on moonbeam
        (address proxy, address implementation) = deployStakedWellMock(
            address(well),
            address(well),
            1 days,
            1 weeks,
            ecosystemReserveProxy, // rewardsVault
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            1 days, // distributionDuration
            address(0), // governance
            proxyAdmin // proxyAdmin
        );

        vm.stopBroadcast();

        addresses.addAddress("STK_GOVTOKEN_IMPL", address(implementation));
        addresses.addAddress("STK_GOVTOKEN", address(proxy));
        addresses.addAddress("ECOSYSTEM_RESERVE_PROXY", address(ecosystemReserveProxy));
        addresses.addAddress("ECOSYSTEM_RESERVE_IMPL", address(ecosystemReserveImplementation));
        addresses.addAddress("ECOSYSTEM_RESERVE_CONTROLLER", address(ecosystemReserveController));

        printAddresses();
    }

    function printAddresses() private view {
        (string[] memory recordedNames,, address[] memory recordedAddresses) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log("        'name': '%s'\n}%s", recordedNames[j], j < recordedNames.length - 1 ? "," : "");
        }
    }
}

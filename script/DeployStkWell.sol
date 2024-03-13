// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

// forge script script/DeployStkWell.sol --rpc-url moonbaseAlpha -vvvv --broadcast -g 200 --slow
contract DeployStkWell is Script, ChainIds, MultichainGovernorDeploy {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public {
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        address well = addresses.getAddress("WELL");

        vm.startBroadcast(PRIVATE_KEY);

        (
            address ecosystemReserveProxy,
            address ecosystemReserveImplementation,
            address ecosystemReserveController
        ) = deployEcosystemReserve(proxyAdmin);

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

        addresses.addAddress("stkWELL_IMPL", address(implementation), true);
        addresses.addAddress("stkWELL", address(proxy), true);
        addresses.addAddress(
            "ECOSYSTEM_RESERVE",
            address(ecosystemReserveProxy),
            true
        );
        addresses.addAddress(
            "ECOSYSTEM_RESERVE_IMPL",
            address(ecosystemReserveImplementation),
            true
        );
        addresses.addAddress(
            "ECOSYSTEM_RESERVE_CONTROLLER",
            address(ecosystemReserveController),
            true
        );

        printAddresses();
    }

    function printAddresses() private view {
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
}

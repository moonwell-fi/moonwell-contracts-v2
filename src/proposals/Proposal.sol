// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";

import "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

abstract contract Proposal is Script, Test {
    using ChainIds for uint256;

    bool internal DEBUG;
    bool internal DO_DEPLOY;
    bool internal DO_AFTER_DEPLOY;
    bool internal DO_BUILD;
    bool internal DO_RUN;
    bool internal DO_TEARDOWN;
    bool internal DO_VALIDATE;
    bool internal DO_PRINT;

    modifier mockHook(Addresses addresses) {
        beforeSimulationHook(addresses);
        _;
        afterSimulationHook(addresses);
    }

    constructor() {
        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_BUILD = vm.envOr("DO_BUILD", true);
        DO_RUN = vm.envOr("DO_RUN", true);
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", true);
        DO_VALIDATE = vm.envOr("DO_VALIDATE", true);
        DO_PRINT = vm.envOr("DO_PRINT", true);
    }

    function run() public virtual {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(primaryForkId());

        initProposal(addresses);

        vm.startBroadcast();

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);
        vm.stopBroadcast();

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public virtual returns (uint256);

    function name() external view virtual returns (string memory);

    function deploy(Addresses, address) public virtual;

    function afterDeploy(Addresses, address) public virtual;

    function build(Addresses) public virtual;

    function run(Addresses, address) public virtual;

    function printCalldata(Addresses addresses) public virtual;

    function teardown(Addresses, address) public virtual;

    function validate(Addresses, address) public virtual;

    function printProposalActionSteps() public virtual;

    function beforeSimulationHook(Addresses) public virtual {}

    function afterSimulationHook(Addresses) public virtual {}

    /// @notice initialize the proposal after the proposal is created and the
    /// live fork is selected
    function initProposal(Addresses) public virtual {}

    /// @dev Print recorded addresses
    function _printAddressesChanges(Addresses addresses) internal view {
        bytes
            memory printedAddress = hex"7b0A20202020202020202261646472223a2022257322";
        bytes
            memory printedName = hex"2020202020202020226e616d65223a20222573220A7d2573";
        bytes
            memory printedContract = hex"2020202020202020226973436f6e7472616374223a202573";

        (
            string[] memory recordedNames,
            uint256[] memory chainIds,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();

        if (recordedNames.length > 0) {
            console.log(
                "\n------- Addresses added after running proposal -------"
            );

            uint256[3] memory chainIdsToCheck = [
                OPTIMISM_CHAIN_ID,
                BASE_CHAIN_ID,
                MOONBEAM_CHAIN_ID
            ];
            string[3] memory chainNames = ["Optimism", "Base", "Moonbeam"];

            for (uint256 i = 0; i < chainIdsToCheck.length; i++) {
                uint256 currentChainId = chainIdsToCheck[i];
                console.log(
                    string(
                        abi.encodePacked(
                            "\n----------- Addresses added for ",
                            chainNames[i],
                            " -----------"
                        )
                    )
                );

                uint256 addressCount = 0;
                for (uint256 j = 0; j < recordedNames.length; j++) {
                    if (chainIds[j] == currentChainId) {
                        addressCount++;
                    }
                }

                uint256 printedCount = 0;
                for (uint256 j = 0; j < recordedNames.length; j++) {
                    if (chainIds[j] == currentChainId) {
                        console.log(
                            string(printedAddress),
                            recordedAddresses[j],
                            ","
                        );
                        console.log(string(printedContract), true, ",");
                        console.log(
                            string(printedName),
                            recordedNames[j],
                            printedCount < addressCount - 1 ? "," : ""
                        );
                        printedCount++;
                    }
                }
            }
        }

        (
            string[] memory changedNames,
            ,
            ,
            address[] memory changedAddresses
        ) = addresses.getChangedAddresses();

        if (changedNames.length > 0) {
            console.log(
                "\n------- Addresses changed after running proposal --------"
            );

            for (uint256 j = 0; j < changedNames.length; j++) {
                console.log(string(printedAddress), changedAddresses[j], ",");
                console.log(string(printedContract), true, ",");
                console.log(
                    string(printedName),
                    changedNames[j],
                    j < changedNames.length - 1 ? "," : ""
                );
            }
        }
    }
}

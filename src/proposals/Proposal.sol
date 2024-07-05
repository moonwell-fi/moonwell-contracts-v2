// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Test} from "@forge-std/Test.sol";

import {ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

abstract contract Proposal is Script, Test {
    using ChainIds for uint256;

    bool private DEBUG;
    bool private DO_DEPLOY;
    bool private DO_AFTER_DEPLOY;
    bool private DO_PRE_BUILD_MOCK;
    bool private DO_BUILD;
    bool private DO_RUN;
    bool private DO_TEARDOWN;
    bool private DO_VALIDATE;
    bool private DO_PRINT;

    /// @notice onchain proposal id for the proposal
    /// returns 0 if proposal has no onchain id. must be set in the proposal
    uint256 public onchainProposalId;

    constructor() {
        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_PRE_BUILD_MOCK = vm.envOr("DO_PRE_BUILD_MOCK", true);
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

        vm.startBroadcast();

        /// TODO triple check this one to make sure it works
        address deployerAddress = msg.sender;

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);
        vm.stopBroadcast();

        if (DO_PRE_BUILD_MOCK) preBuildMock(addresses);
        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            {
                uint256[] memory allowedChainIds = new uint256[](3);
                allowedChainIds[0] = block.chainid.toBaseChainId();
                allowedChainIds[1] = block.chainid.toOptimismChainId();
                allowedChainIds[2] = block.chainid.toMoonbeamChainId();

                addresses.addRestrictions(allowedChainIds);
                printCalldata(addresses);
                addresses.removeRestriction();
            }

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public pure virtual returns (uint256);

    function name() external view virtual returns (string memory);

    function deploy(Addresses, address) public virtual;

    function afterDeploy(Addresses, address) public virtual;

    function preBuildMock(Addresses) public virtual;

    function build(Addresses) public virtual;

    function run(Addresses, address) public virtual;

    function printCalldata(Addresses addresses) public virtual;

    function teardown(Addresses, address) public virtual;

    function validate(Addresses, address) public virtual;

    function printProposalActionSteps() public virtual;

    // @notice search for a on-chain proposal that matches the proposal calldata
    // @returns the proposal id, 0 if no proposal is found
    function getProposalId(
        Addresses,
        address
    ) public virtual returns (uint256 proposalId);

    /// @dev Print recorded addresses
    function _printAddressesChanges(Addresses addresses) private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();

        if (recordedNames.length > 0) {
            console.log(
                "\n-------- Addresses added after running proposal --------"
            );
            for (uint256 j = 0; j < recordedNames.length; j++) {
                console.log(
                    "{\n          'addr': '%s', ",
                    recordedAddresses[j]
                );
                console.log("        'chainId': %d,", block.chainid);
                console.log("        'isContract': %s", true, ",");
                console.log(
                    "        'name': '%s'\n}%s",
                    recordedNames[j],
                    j < recordedNames.length - 1 ? "," : ""
                );
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
                console.log("{\n          'addr': '%s', ", changedAddresses[j]);
                console.log("        'chainId': %d,", block.chainid);
                console.log("        'isContract': %s", true, ",");
                console.log(
                    "        'name': '%s'\n}%s",
                    changedNames[j],
                    j < changedNames.length - 1 ? "," : ""
                );
            }
        }
    }
}

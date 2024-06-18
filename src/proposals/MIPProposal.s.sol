// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@proposals/Addresses.sol";

/*
How to use:
forge script src/proposals/MIPProposal.s.sol:DeployProposal \
    -vvvv \
    --rpc-url $ETH_RPC_URL \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.

to verify after deploy:
  forge verify-contract --etherscan-api-key $BASESCAN_API_KEY \ 
        <deployed contract address> src/MWethDelegate.sol:MWethDelegate
        --chain 8453

*/
abstract contract MIPProposal is Script {
    enum ProposalType {
        Moonbeam,
        Base,
        Optimism
    }

    Addresses public addresses;

    uint256 private PRIVATE_KEY;

    bool private DEBUG;
    bool private DO_DEPLOY;
    bool private DO_AFTER_DEPLOY;
    bool private DO_PRE_BUILD_MOCK;
    bool private DO_BUILD;
    bool private DO_RUN;
    bool private DO_TEARDOWN;
    bool private DO_VALIDATE;
    bool private DO_PRINT;

    constructor() {
        PRIVATE_KEY = uint256(vm.envOr("ETH_PRIVATE_KEY", uint256(123)));

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
        vm.createFork(vm.envOr("MOONBEAM_RPC_URL", string("moonbeam")));

        vm.createFork(vm.envOr("BASE_RPC_URL", string("base")));

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(uint256(primaryForkId()));

        address deployerAddress = vm.addr(PRIVATE_KEY);

        console.log("deployerAddress: ", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);
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
            printCalldata(addresses);
            _printAddressesChanges();
        }
    }

    function primaryForkId() public pure virtual returns (ProposalType);

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
    function _printAddressesChanges() private view {
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

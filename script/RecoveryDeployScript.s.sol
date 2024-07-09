pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Recovery} from "@protocol/Recovery.sol";
import {RecoveryDeploy} from "@test/utils/RecoveryDeploy.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 to simulate:
    forge script script/RecoveryDeployScript.s.sol:RecoveryDeployScript \
     \ -vvvvv --rpc-url base --with-gas-price 500000
 to run:
    forge script script/RecoveryDeployScript.s.sol:RecoveryDeployScript \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
contract RecoveryDeployScript is Script, Test, RecoveryDeploy {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public returns (Recovery recovery) {
        address foundationMultisig = addresses.getAddress(
            "FOUNDATION_MULTISIG"
        );

        vm.startBroadcast();

        (, address deployerAddress, ) = vm.readCallers();

        /// send all 1901 tx's, then deploy
        recovery = mainnetDeployAndVerifyScript(deployerAddress);

        uint256 recoveryBalance = address(recovery).balance;
        uint256 multisigStartingBalance = foundationMultisig.balance;

        recovery.sendAllEth(payable(foundationMultisig));
        vm.stopBroadcast();

        /// should have sent 1902 transactions
        assertEq(vm.getNonce(deployerAddress), 1903, "incorrect nonce");
        assertEq(
            recoveryBalance,
            foundationMultisig.balance - multisigStartingBalance,
            "recovery balance not given to foundation multisig"
        );
        assertEq(address(recovery).balance, 0, "recovery balance not 0");
    }
}

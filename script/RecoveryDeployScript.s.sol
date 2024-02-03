pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Recovery} from "@protocol/Recovery.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {RecoveryDeploy} from "@test/utils/RecoveryDeploy.sol";

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

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "ETH_PRIVATE_KEY",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );

        addresses = new Addresses();
    }

    function run() public returns (Recovery recovery) {
        address foundationMultisig = addresses.getAddress(
            "FOUNDATION_MULTISIG"
        );

        address deployerAddress = vm.addr(PRIVATE_KEY);

        vm.startBroadcast(PRIVATE_KEY);

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

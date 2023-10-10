pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Recovery} from "@protocol/Recovery.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {RecoveryDeploy} from "@test/utils/RecoveryDeploy.sol";

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

        vm.startBroadcast(deployer);
        /// send all 1901 tx's, then deploy
        recovery = mainnetDeployAndVerifyScript(deployer);

        uint256 recoveryBalance = address(recovery).balance;
        uint256 multisigStartingBalance = foundationMultisig.balance;

        recovery.sendAllEth(payable(foundationMultisig));
        vm.stopBroadcast();

        /// should have sent 1902 transactions
        assertEq(vm.getNonce(deployer), 1903, "incorrect nonce");
        assertEq(
            recoveryBalance,
            multisigStartingBalance,
            "recovery balance not given to foundation multisig"
        );
        assertEq(address(recovery).balance, 0, "recovery balance not 0");
    }
}

pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
 to simulate:
    forge script script/WellDeployerNonceIncrement.s.sol:WellDeployerNonceIncrement \
     \ -vvvvv --rpc-url base --with-gas-price 500000
 to run:
    forge script script/WellDeployerNonceIncrement.s.sol:WellDeployerNonceIncrement \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
contract WellDeployerNonceIncrement is Script, Test {
    function run() public {
        Addresses addresses = new Addresses();
        uint256 expectedNonce = 387;

        vm.startBroadcast();

        (, address deployerAddress, ) = vm.readCallers();

        uint256 currentNonce = vm.getNonce(deployerAddress);
        uint256 increment = expectedNonce - currentNonce;

        for (uint256 i = 0; i < increment; i++) {
            (bool success, ) = address(deployerAddress).call{value: 1}("");
            success;
            console.log(vm.getNonce(deployerAddress));
        }
        vm.stopBroadcast();

        assertEq(
            vm.getNonce(deployerAddress),
            expectedNonce,
            "incorrect nonce"
        );
    }
}

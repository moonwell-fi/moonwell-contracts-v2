pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";

contract ExecuteCalldata is Script, Test {
    /// @notice executor private key
    uint256 private PRIVATE_KEY;

    constructor() {
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));
    }

    function run() public {
        bytes memory data = vm.envBytes("CALLDATA");
        address target = vm.envAddress("TARGET");

        vm.startBroadcast(PRIVATE_KEY);
        (bool success, ) = address(target).call(data);
        require(success, "Call failed");
        vm.stopBroadcast();
    }
}

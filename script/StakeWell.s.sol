pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract StakeWell is Script, Test {
    /// @notice executor private key
    uint256 private PRIVATE_KEY;

    Addresses addresses;

    constructor() {
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        address stkWell = addresses.getAddress("STK_GOVTOKEN");
        address xwell = addresses.getAddress("xWELL_PROXY");

        bytes memory data = abi.encodeWithSignature(
            "stake(address,uint256)",
            vm.addr(PRIVATE_KEY),
            50_000 * 1e18
        );

        bytes memory approveData = abi.encodeWithSignature(
            "approve(address,uint256)",
            stkWell,
            50_000 * 1e18
        );
        vm.startBroadcast(PRIVATE_KEY);
        (bool successApprove, ) = address(xwell).call(approveData);

        require(successApprove, "Call failed");

        (bool success, bytes memory result) = address(stkWell).call(data);
        vm.stopBroadcast();

        require(success, "Call failed");
        console.log(string(result));
    }
}

pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {CreateCode} from "@proposals/utils/CreateCode.sol";

contract CreationCodeUnitTest is CreateCode {
    function testDeployCode() public {
        string memory path = getPath(); /// load path from env
        if (bytes(path).length == 0) {
            path = "artifacts/foundry/mip-b07.sol/mipb07.json";
        }
        bytes memory code = getCode(path); /// load creation bytecode into memory

        address deployedAddress = deployCode(code);

        (bool success, ) = deployedAddress.call(
            abi.encodeWithSignature(
                "teardown(address,address)",
                address(0),
                address(0)
            )
        );

        require(
            success,
            "Teardown failed, are you sure you passed a valid proposal path?"
        );
    }
}

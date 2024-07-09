//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

bytes32 constant _ADMIN_SLOT =
    0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

bytes32 constant _IMPLEMENTATION_SLOT =
    0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

function validateProxy(
    Vm vm,
    address proxy,
    address logic,
    address admin,
    string memory error
) view {
    {
        bytes32 data = vm.load(proxy, _ADMIN_SLOT);

        require(
            bytes32(uint256(uint160(admin))) == data,
            string(abi.encodePacked(error, " admin not set correctly"))
        );
    }

    {
        bytes32 data = vm.load(proxy, _IMPLEMENTATION_SLOT);

        require(
            bytes32(uint256(uint160(logic))) == data,
            string(abi.encodePacked(error, " logic contract not set correctly"))
        );
    }
}

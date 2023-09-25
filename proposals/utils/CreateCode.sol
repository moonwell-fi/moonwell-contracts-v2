pragma solidity 0.8.19;

import "@forge-std/Test.sol";

/// @notice helper to deploy a contract from its creation bytecode
/// based on the path to the proposal artifact
contract CreateCode is Test {
    /// @notice returns the path to the proposal artifact based on the environment variable
    function getPath() public view returns (string memory) {
        return vm.envString("PROPOSAL_ARTIFACT_PATH");
    }

    /// @notice returns the creation bytecode of the contract based on the path
    function getCode(string memory path) public view returns (bytes memory) {
        return vm.getCode(path);
    }

    /// @notice returns the address of the deployed contract based on the creation bytecode
    /// @dev example usage:
    /// string memory path = getPath(); /// load path from env
    /// bytes memory code = getCode(path); /// load creation bytecode into memory
    /// address deployedAddress = deployCode(code);
    /// @param code the creation bytecode of the contract
    function deployCode(bytes memory code) public returns (address) {
        address deployedAddress;
        assembly {
            /// get size of creation bytecode
            let size := mload(code)
            /// ignore first 32 bytes of creation bytecode which declares its length
            let data := add(code, 0x20)
            /// create and send 0 value
            deployedAddress := create(0, data, size)
        }

        /// sanity check that deployment succeeded
        require(
            deployedAddress != address(0),
            "Contract deployment failed, are you sure you passed a valid proposal path?"
        );

        return deployedAddress;
    }
}

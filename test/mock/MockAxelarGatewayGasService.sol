// SPDX-License-Identifier: UNLICENSED
// FILEPATH: test/mock/MockAxelarGatewayGasService.sol
pragma solidity 0.8.19;

contract MockAxelarGatewayGasService {
    function payNativeGasForContractCall(
        address sender,
        string calldata destinationChain,
        string calldata destinationAddress,
        bytes calldata payload,
        address refundAddress
    ) external payable {
        /// no-op
    }

    function callContract(
        string calldata destinationChain,
        string calldata contractAddress,
        bytes calldata payload
    ) external {
        /// no-op
    }

    bool public validate = true;

    function setValidate(bool _validate) external {
        validate = _validate;
    }

    function validateContractCall(
        bytes32,
        string calldata,
        string calldata,
        bytes32
    ) external view returns (bool) {
        return validate;
    }
}

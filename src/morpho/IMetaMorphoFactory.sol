// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

interface IMetaMorphoFactory {
    function createMetaMorpho(
        address initialOwner,
        uint256 initialTimelock,
        address asset,
        string memory name,
        string memory symbol,
        bytes32 salt
    ) external returns (address);
}

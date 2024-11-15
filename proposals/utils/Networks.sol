// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

abstract contract Networks is Test {
    struct Network {
        uint256 chainId;
        uint256 forkId;
        string name;
        uint16 wormholeChainId;
    }

    /// @notice list of supported networks to be used by proposal contracts,
    /// specifically xWELL deployment
    Network[] public networks;

    constructor() {
        string memory data = vm.readFile(
            VMSafe(address(vm)).envOr(
                "NETWORK_PATH",
                "./chains/mainnetchains.json"
            )
        );
        bytes memory parsedJson = vm.parseJson(data);

        Network[] memory jsonNetworks = abi.decode(parsedJson, (Network[]));
        for (uint256 i = 0; i < jsonNetworks.length; i++) {
            networks.push(jsonNetworks[i]);
        }
    }
}

interface VMSafe {
    /// Gets the environment variable `name` and parses it as `string`.
    /// Reverts if the variable could not be parsed.
    /// Returns `defaultValue` if the variable was not found.
    function envOr(
        string calldata name,
        string calldata defaultValue
    ) external view returns (string memory);
}

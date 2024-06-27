// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@protocol/utils/Constants.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

/// NOTE: this script is only deployable on optimism and optimism sepolia
/// to expand functionality, add the allowed chainIds to the chainIds array

/*
How to use:
COMPOSITE_ORACLE=CHAINLINK_WSTETH_ETH forge script src/proposals/DeployConfigurableEthCompositeOracle.s.sol:DeployConfigurableEthCompositeOracle \
    -vvvv \
    --rpc-url optimism \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
Substitute in the COMPOSITE_ORACLE address you want to use.
*/

contract DeployConfigurableEthCompositeOracle is Script, ChainIds {
    Addresses addresses;

    /// only allow deployment on optimism and optimism sepolia
    uint256[] public chainIds = [optimismChainId, optimismSepoliaChainId];

    function setUp() public {
        addresses = new Addresses(chainIds);
    }

    function run() public returns (ChainlinkCompositeOracle) {
        vm.startBroadcast();
        ChainlinkCompositeOracle clco = new ChainlinkCompositeOracle(
            addresses.getAddress("CHAINLINK_ETH_USD"),
            addresses.getAddress(vm.envString("COMPOSITE_ORACLE")),
            address(0) /// only 2 oracles for this composite oracle
        );

        console.log(
            "successfully deployed chainlink composite oracle: %s, using %s",
            address(clco),
            vm.envString("COMPOSITE_ORACLE")
        );

        vm.stopBroadcast();

        (, int256 price, , , ) = clco.latestRoundData();

        console.log("price: %d", uint256(price)); /// sanity check that params are correct

        return clco;
    }
}

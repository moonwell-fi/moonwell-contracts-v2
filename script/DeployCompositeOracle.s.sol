// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
How to use:
forge script script/DeployCompositeOracle.s.sol:DeployCompositeOracle \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployCompositeOracle is Script {
    function run() public returns (ChainlinkCompositeOracle) {
        Addresses addresses = new Addresses();

        vm.startBroadcast();
        ChainlinkCompositeOracle clco = new ChainlinkCompositeOracle(
            addresses.getAddress("CHAINLINK_ETH_USD"),
            addresses.getAddress("CHAINLINK_WEETH_ORACLE"),
            address(0) /// only 2 oracles for this composite oracle
        );

        console.log(
            "successfully deployed chainlink composite oracle: %s",
            address(clco)
        );

        vm.stopBroadcast();

        (, int256 price, , , ) = clco.latestRoundData();

        console.log("price: %d", uint256(price)); /// sanity check that params are correct

        return clco;
    }
}

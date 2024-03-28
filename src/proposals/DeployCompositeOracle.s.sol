// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

/*
How to use:
forge script src/proposals/DeployCompositeOracle.s.sol:DeployCompositeOracle \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployCompositeOracle is Script {
    uint256 public PRIVATE_KEY;
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(
            vm.envOr(
                "MOONWELL_DEPLOY_PK",
                bytes32(
                    0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
                )
            )
        );
    }

    function run() public returns (ChainlinkCompositeOracle) {
        vm.startBroadcast(PRIVATE_KEY);
        ChainlinkCompositeOracle clco = new ChainlinkCompositeOracle(
            addresses.getAddress("CHAINLINK_ETH_USD"),
            addresses.getAddress("CHAINLINK_RETH_ETH"),
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

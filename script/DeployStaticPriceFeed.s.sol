// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {StaticPriceFeed} from "@protocol/oracles/StaticPriceFeed.sol";

/*
Deploys a StaticPriceFeed for MOVR on Moonriver.
Used to replace the deprecated Chainlink feed via oracle.setFeed("mMOVR", deployed).

to run:
forge script script/DeployStaticPriceFeed.s.sol:DeployStaticPriceFeed -vvvv --rpc-url moonriver --broadcast
*/

contract DeployStaticPriceFeed is Script {
    /// @notice MOVR price in 8-decimal Chainlink format ($1.25 = 1.25 * 1e8)
    int256 public constant MOVR_PRICE = 125000000;

    function run() public {
        vm.startBroadcast();

        StaticPriceFeed feed = new StaticPriceFeed(MOVR_PRICE, "MOVR / USD");

        vm.stopBroadcast();

        console.log("StaticPriceFeed deployed at:", address(feed));
        console.log("  answer:", uint256(feed.staticAnswer()));
        console.log("  decimals:", feed.decimals());
        console.log("  description:", feed.description());
    }
}

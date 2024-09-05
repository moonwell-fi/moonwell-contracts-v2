// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {MarketAddChecker} from "@protocol/governance/MarketAddChecker.sol";

/*
How to use:
forge script script/DeployMarketAddChecker.s.sol:DeployMarketAddChecker \
    -vvvv \
    --rpc-url base \
    --broadcast --etherscan-api-key $chainAlias --verify
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployMarketAddChecker is Script {
    bytes32 public constant salt = keccak256("MARKET_ADD_CHECKER");

    function run() public {
        vm.startBroadcast();

        MarketAddChecker checker = new MarketAddChecker{salt: salt}();

        vm.stopBroadcast();

        console.log(
            "successfully deployed Market Add Checker: %s",
            address(checker)
        );
    }
}

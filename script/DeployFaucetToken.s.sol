// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";

/*
How to use:
forge script script/DeployFaucetToken.s.sol:DeployFaucetToken \
    -vvvv \
    --rpc-url base \
    --broadcast
Remove --broadcast if you want to try locally first, without paying any gas.
*/

contract DeployFaucetToken is Script {
    string public symbol;
    string public name;
    uint256 public initialMintAmount;
    uint8 public decimals;

    function setUp() public {
        symbol = string(vm.envOr("SYMBOL", bytes("DAI")));
        name = string(vm.envOr("NAME", bytes("DAI Faucet Token")));
        initialMintAmount = vm.envOr(
            "INITIAL_MINT_AMOUNT",
            uint256(100_000_000e18)
        );
        decimals = uint8(vm.envOr("DECIMALS", uint8(18)));
    }

    function run() public {
        vm.startBroadcast();
        FaucetTokenWithPermit token = new FaucetTokenWithPermit(
            initialMintAmount,
            name,
            decimals,
            symbol
        );

        vm.stopBroadcast();

        console.log("successfully deployed FaucetToken: %s", address(token));

        console.log("name: %s", name);
        console.log("symbol: %s", symbol);
        console.log("decimals: %d", decimals);
        console.log("initialMintAmount: %d", initialMintAmount);
    }
}

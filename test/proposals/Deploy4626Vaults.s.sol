// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@test/proposals/Addresses.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Compound4626Deploy} from "@protocol/4626/4626Deploy.sol";

/*
How to use:
1. set REWARDS_RECEIVER to the address you want to receive rewards in Addresses.sol
2. run:
forge script test/proposals/Deploy4626Vaults.s.sol:Deploy4626Vaults \
    -vvvv \
    --rpc-url base \
    --broadcast --etherscan-api-key base --verify
Remove `--broadcast --etherscan-api-key base --verify` if you want to try locally
 first, without paying any gas.
*/

contract Deploy4626Vaults is Script, Compound4626Deploy, Test {
    uint256 public PRIVATE_KEY;
    Addresses addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);
        address rewardRecipient = addresses.getAddress("REWARDS_RECEIVER");

        console.log("deployer address: %s", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);

        deployVaults(addresses, rewardRecipient);

        address unitroller = addresses.getAddress("UNITROLLER");

        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("USDC_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("USDC"));
            assertEq(address(vault.mToken()), addresses.getAddress("MOONWELL_USDC"));
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed USDC vault: ", address(vault));
        }
        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("WETH_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("WETH"));
            assertEq(address(vault.mToken()), addresses.getAddress("MOONWELL_WETH"));
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed WETH vault: ", address(vault));
        }
        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("cbETH_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("cbETH"));
            assertEq(address(vault.mToken()), addresses.getAddress("MOONWELL_cbETH"));
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed cbETH vault: ", address(vault));
        }

        vm.stopBroadcast();
    }
}

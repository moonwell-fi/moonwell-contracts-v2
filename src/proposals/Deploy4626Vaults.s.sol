// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Compound4626Deploy} from "@protocol/4626/4626Deploy.sol";

/*
How to use:
1. set REWARDS_RECEIVER to the address you want to receive rewards in Addresses.sol
2. run:
forge script src/proposals/Deploy4626Vaults.s.sol:Deploy4626Vaults \
    -vvvv \
    --rpc-url base \
    --broadcast --etherscan-api-key base --verify
Remove `--broadcast --etherscan-api-key base --verify` if you want to try locally
 first, without paying any gas.
*/

contract Deploy4626Vaults is Script, Compound4626Deploy, Test {
    uint256 public PRIVATE_KEY;
    uint256 public constant INITIAL_MINT_AMOUNT_USDBC = 1e6;
    uint256 public constant INITIAL_MINT_AMOUNT_WETH = 1e12;
    uint256 public constant INITIAL_MINT_AMOUNT_CBETH = 1e12;

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

        if (vm.envBool("MOONWELL_DEPLOY_MINT")) {
            deal(
                addresses.getAddress("USDBC"),
                deployerAddress,
                INITIAL_MINT_AMOUNT_USDBC
            );
            deal(
                addresses.getAddress("WETH"),
                deployerAddress,
                INITIAL_MINT_AMOUNT_WETH
            );
            deal(
                addresses.getAddress("cbETH"),
                deployerAddress,
                INITIAL_MINT_AMOUNT_CBETH
            );
        }

        vm.startBroadcast(PRIVATE_KEY);

        deployVaults(addresses, rewardRecipient);

        address unitroller = addresses.getAddress("UNITROLLER");

        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("USDBC_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("USDBC"));
            assertEq(
                address(vault.mToken()),
                addresses.getAddress("MOONWELL_USDBC")
            );
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed USDBC vault: ", address(vault));

            ERC20 usdc = ERC20(addresses.getAddress("USDBC"));
            usdc.approve(address(vault), INITIAL_MINT_AMOUNT_USDBC);
            vault.deposit(INITIAL_MINT_AMOUNT_USDBC, deployerAddress);
        }

        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("WETH_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("WETH"));
            assertEq(
                address(vault.mToken()),
                addresses.getAddress("MOONWELL_WETH")
            );
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed WETH vault: ", address(vault));

            ERC20 weth = ERC20(addresses.getAddress("WETH"));
            weth.approve(address(vault), INITIAL_MINT_AMOUNT_WETH);
            vault.deposit(INITIAL_MINT_AMOUNT_WETH, deployerAddress);
        }

        {
            CompoundERC4626 vault = CompoundERC4626(
                addresses.getAddress("cbETH_VAULT")
            );
            assertEq(address(vault.asset()), addresses.getAddress("cbETH"));
            assertEq(
                address(vault.mToken()),
                addresses.getAddress("MOONWELL_cbETH")
            );
            assertEq(address(vault.comptroller()), unitroller);
            assertEq(vault.rewardRecipient(), rewardRecipient);

            console.log("deployed cbETH vault: ", address(vault));

            ERC20 cbeth = ERC20(addresses.getAddress("cbETH"));
            cbeth.approve(address(vault), INITIAL_MINT_AMOUNT_WETH);
            vault.deposit(INITIAL_MINT_AMOUNT_CBETH, deployerAddress);
        }

        vm.stopBroadcast();
    }
}

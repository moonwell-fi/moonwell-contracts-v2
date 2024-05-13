// SPDX-License-Iden`fier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {Proxy} from "@external/Proxy.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IMetaMorpho} from "@external/MetaMorpho.sol";

contract MorphoVaultLiveSystemBaseTest is Configs {
    Addresses addresses;
    IMetaMorpho metaMorpho;
    IMetaMorpho usdcVault;
    address morpho;
    IERC20 usdc;

    uint256 public constant timelock = 2 days;

    function setUp() public {
        addresses = new Addresses();

        morpho = addresses.getAddress("MORPHO_BLUE");
        usdc = IERC20(addresses.getAddress("USDC"));
        metaMorpho = IMetaMorpho(
            addresses.getAddress("METAMORPHO_USDC_VAULT_TESTNET")
        );
        usdcVault = IMetaMorpho(
            address(
                new Proxy(
                    address(morpho),
                    address(metaMorpho),
                    addresses.getAddress("MRD_PROXY_ADMIN"),
                    address(this),
                    timelock,
                    address(usdc),
                    "Moonwell USDC Vault",
                    "Moonwell-USDC"
                )
            )
        );
    }

    function testSetup() public {
        // assertEq(usdcVault.admin(), address(this));
        assertEq(usdcVault.owner(), address(this));
        assertEq(usdcVault.timelock(), timelock);
        assertEq(usdcVault.asset(), address(usdc));
        assertEq(usdcVault.totalSupply(), 0);
        {
            bytes32 val = vm.load(
                addresses.getAddress("METAMORPHO_USDC_VAULT_TESTNET"),
                bytes32(uint256(3))
            );
            console.log("original name: ");
            console.logBytes32(val);
        }

        {
            bytes32 val = vm.load(
                addresses.getAddress("METAMORPHO_USDC_VAULT_TESTNET"),
                bytes32(uint256(4))
            );
            console.log("original symbol: ");
            console.logBytes32(val);
        }
        {
            bytes32 val = vm.load(address(usdcVault), bytes32(uint256(3)));
            console.log("name: ");
            console.logBytes32(val);
        }

        {
            bytes32 val = vm.load(address(usdcVault), bytes32(uint256(4)));
            console.log("symbol: ");
            console.logBytes32(val);
        }

        assertEq(usdcVault.symbol(), "Moonwell-USDC");
        assertEq(usdcVault.name(), "Moonwell USDC Vault");
    }

    function testMint() public {}
}

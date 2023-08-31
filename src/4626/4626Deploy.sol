pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract Compound4626Deploy {
    function deployVaults(
        Addresses addresses,
        address owner,
        address rewardHandler
    ) public {
        /// deploy the ERC20 wrapper for USDC
        CompoundERC4626 usdcVault = new CompoundERC4626(
            owner,
            ERC20(addresses.getAddress("USDC")),
            MErc20(addresses.getAddress("MOONWELL_USDC")),
            IComptroller(addresses.getAddress("UNITROLLER")),
            rewardHandler
        );

        CompoundERC4626 wethVault = new CompoundERC4626(
            owner,
            ERC20(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH")),
            IComptroller(addresses.getAddress("UNITROLLER")),
            rewardHandler
        );

        CompoundERC4626 cbethVault = new CompoundERC4626(
            owner,
            ERC20(addresses.getAddress("cbETH")),
            MErc20(addresses.getAddress("MOONWELL_cbETH")),
            IComptroller(addresses.getAddress("UNITROLLER")),
            rewardHandler
        );

        addresses.addAddress("USDC_VAULT", address(usdcVault));
        addresses.addAddress("WETH_VAULT", address(wethVault));
        addresses.addAddress("cbETH_VAULT", address(cbethVault));
    }
}

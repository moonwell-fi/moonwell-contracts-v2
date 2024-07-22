pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MoonwellERC4626} from "@protocol/4626/MoonwellERC4626.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract Compound4626Deploy {
    function deployVaults(Addresses addresses, address rewardReceiver) public {
        /// deploy the ERC20 wrapper for USDBC
        MoonwellERC4626 usdcVault = new MoonwellERC4626(
            ERC20(addresses.getAddress("USDBC")),
            MErc20(addresses.getAddress("MOONWELL_USDBC")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        MoonwellERC4626 wethVault = new MoonwellERC4626(
            ERC20(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        MoonwellERC4626 cbethVault = new MoonwellERC4626(
            ERC20(addresses.getAddress("cbETH")),
            MErc20(addresses.getAddress("MOONWELL_cbETH")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        addresses.addAddress("USDBC_VAULT", address(usdcVault));
        addresses.addAddress("WETH_VAULT", address(wethVault));
        addresses.addAddress("cbETH_VAULT", address(cbethVault));
    }
}

pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {CompoundERC4626} from "@protocol/4626/CompoundERC4626.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract Compound4626Deploy {
    function deployVaults(Addresses addresses, address rewardReceiver) public {
        /// deploy the ERC20 wrapper for USDBC
        CompoundERC4626 usdcVault = new CompoundERC4626(
            ERC20(addresses.getAddress("USDBC")),
            MErc20(addresses.getAddress("MOONWELL_USDBC")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        CompoundERC4626 wethVault = new CompoundERC4626(
            ERC20(addresses.getAddress("WETH")),
            MErc20(addresses.getAddress("MOONWELL_WETH")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        CompoundERC4626 cbethVault = new CompoundERC4626(
            ERC20(addresses.getAddress("cbETH")),
            MErc20(addresses.getAddress("MOONWELL_cbETH")),
            rewardReceiver,
            IComptroller(addresses.getAddress("UNITROLLER"))
        );

        addresses.addAddress("USDBC_VAULT", address(usdcVault), true);
        addresses.addAddress("WETH_VAULT", address(wethVault), true);
        addresses.addAddress("cbETH_VAULT", address(cbethVault), true);
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MarketAddV2} from "@proposals/templates/MarketAddV2.sol";
import "@protocol/utils/ChainIds.sol";

/// @title MIP-B59: Add VVV Market to Moonwell on Base
/// @notice Override beforeSimulationHook to use stdstore for Solmate ERC20 compatibility
contract mipb59 is MarketAddV2 {
    using ChainIds for uint256;
    using stdStorage for StdStorage;

    function beforeSimulationHook(Addresses addresses) public override {
        uint256 forkBefore = vm.activeFork();
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            vm.selectFork(chainId.toForkId());

            for (uint256 j = 0; j < mTokens[chainId].length; j++) {
                MTokenConfiguration memory config = mTokens[chainId][j];

                /// Use stdstore instead of deal() for Solmate ERC20 compatibility.
                /// VVV uses Solmate's ERC20 which has a different storage layout
                /// than OpenZeppelin's, causing deal() to set the wrong slot.
                stdstore
                    .target(addresses.getAddress(config.tokenAddressName))
                    .sig("balanceOf(address)")
                    .with_key(addresses.getAddress("TEMPORAL_GOVERNOR"))
                    .checked_write(config.initialMintAmount);
            }
        }

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
    }
}

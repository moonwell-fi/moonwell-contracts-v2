// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MarketAddTemplate} from "proposals/templates/MarketAdd.sol";

contract MockRedstoneFeed {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, 100_000e8, 0, block.timestamp, 0);
    }
}

contract mipb40 is MarketAddTemplate {
    function beforeSimulationHook(Addresses addresses) public override {
        MockRedstoneFeed redstoneMock = new MockRedstoneFeed();

        vm.etch(
            addresses.getAddress("REDSTONE_LBTC_BTC", 8453),
            address(redstoneMock).code
        );
        super.beforeSimulationHook(addresses);
    }
}

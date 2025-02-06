// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MarketAddTemplate} from "proposals/templates/MarketAdd.sol";

contract MockMultiFeedAdapterWithoutRounds {
    function getLastUpdateDetails(
        bytes32
    )
        public
        view
        virtual
        returns (
            uint256 lastDataTimestamp,
            uint256 lastBlockTimestamp,
            uint256 lastValue
        )
    {
        return (block.timestamp, block.timestamp, 100_000e8);
    }
}

contract mipb40 is MarketAddTemplate {
    function beforeSimulationHook(Addresses addresses) public override {
        uint256 forkBefore = vm.activeFork();
        vm.selectFork(BASE_FORK_ID);

        MockMultiFeedAdapterWithoutRounds redstoneMock = new MockMultiFeedAdapterWithoutRounds();

        vm.etch(
            0xf030a9ad2707c6C628f58372Fa3B355264417f56,
            address(redstoneMock).code
        );

        if (vm.activeFork() != forkBefore) {
            vm.selectFork(forkBefore);
        }
        super.beforeSimulationHook(addresses);
    }
}

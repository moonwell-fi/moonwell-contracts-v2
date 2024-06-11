// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {MarketParams} from "@protocol/morpho/IMetaMorpho.sol";

interface IMorphoBlue {
    function createMarket(MarketParams memory marketParams) external;
}

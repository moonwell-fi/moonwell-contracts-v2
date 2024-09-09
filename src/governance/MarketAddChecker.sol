pragma solidity 0.8.19;

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

/// @notice stateless contract to check that all markets are correctly
/// initialized. Do this by checking that the total supply is greater
/// than zero, and that the address(0) has a balance greater than zero.
contract MarketAddChecker {
    /// @notice check that a market has been correctly initialized
    /// @param market address of the market to check
    function checkMarketAdd(address market) public view {
        require(MToken(market).totalSupply() > 0, "Zero total supply");
        require(MToken(market).balanceOf(address(0)) > 0, "No balance burnt");
    }

    /// @notice check all markets in a given comptroller
    /// @param comptroller address to check
    function checkAllMarkets(address comptroller) public view {
        MToken[] memory markets = Comptroller(comptroller).getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            checkMarketAdd(address(markets[i]));
        }
    }
}

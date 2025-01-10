pragma solidity =0.8.19;

import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {ERC20HoldingDeposit} from "@protocol/market/ERC20HoldingDeposit.sol";

contract AutomationDeploy {
    function deployReserveAutomation(
        ReserveAutomation.InitParams memory params
    ) public returns (address) {
        require(params.wellToken.code.length > 0, "wellToken must be set");
        require(params.reserveAsset.code.length > 0, "mToken must be set");
        require(
            params.wellChainlinkFeed.code.length > 0,
            "wellChainlinkFeed must be set"
        );
        require(
            params.reserveChainlinkFeed.code.length > 0,
            "reserveChainlinkFeed must be set"
        );
        require(
            params.recipientAddress.code.length > 0,
            "recipientAddress must be set"
        );
        require(
            params.mTokenMarket.code.length > 0,
            "mTokenMarket must be set"
        );
        require(params.owner != address(0), "owner must be set");
        require(params.guardian != address(0), "guardian must be set");

        require(
            params.maxDiscount <= 1e17,
            "maxDiscount must be less than 10%"
        );
        require(
            params.discountApplicationPeriod > 0,
            "discountApplicationPeriod must be greater than 0"
        );

        require(
            params.discountApplicationPeriod <= 2 weeks,
            "discountApplicationPeriod must be less than 2 weeks"
        );
        require(
            params.nonDiscountPeriod <= 2 weeks,
            "non discount period cannot be greater than sale period"
        );

        require(
            params.nonDiscountPeriod + params.discountApplicationPeriod <
                2 weeks,
            "discount and non discount period should be less than 2 weeks"
        );

        ReserveAutomation automation = new ReserveAutomation(params);
        return address(automation);
    }

    function deployERC20HoldingDeposit(
        address token,
        address owner
    ) public returns (address) {
        require(token.code.length > 0, "token must be set");
        return address(new ERC20HoldingDeposit(token, owner));
    }
}

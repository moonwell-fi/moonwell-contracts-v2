pragma solidity =0.8.19;

import {MErc20Storage} from "@protocol/MTokenInterfaces.sol";
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
            params.reserveChainlinkFeed != address(0),
            "reserveChainlinkFeed address not set"
        );
        require(
            params.recipientAddress.code.length > 0,
            "recipientAddress must be set"
        );
        require(
            params.mTokenMarket.code.length > 0,
            "mTokenMarket must be set"
        );
        require(
            MErc20Storage(params.mTokenMarket).underlying() ==
                params.reserveAsset,
            "reserveUnderlying must match mToken underlying"
        );
        require(params.owner != address(0), "owner must be set");
        require(params.guardian != address(0), "guardian must be set");

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

pragma solidity 0.8.19;

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";

contract DeployChainlinkOEVWrapper {
    function deployChainlinkOEVWrapper(
        Addresses addresses,
        string memory feed
    ) public returns (ChainlinkFeedOEVWrapper wrapper) {
        wrapper = new ChainlinkFeedOEVWrapper(
            addresses.getAddress(feed),
            99,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("MOONWELL_WETH"),
            addresses.getAddress("WETH"),
            uint8(10),
            uint8(10)
        );

        addresses.addAddress(
            string(abi.encodePacked(feed, "_OEV_WRAPPER")),
            address(wrapper)
        );
    }
}

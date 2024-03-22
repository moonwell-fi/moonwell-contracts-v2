pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {BreakGlassCalldata} from "@protocol/utils/BreakGlassCalldata.sol";

/// Performs the following actions which hand off direct or pending ownership
/// of the contracts from the Multichain Governor to the Artemis Timelock contract:
///    1. calls executeBreakGlass on the governor, which:
///      a. calls set trusted sender on temporal governor through wormhole core
///      b. calls set pending admin of all mTokens on moonbeam
///      c. sets the admin of chainlink oracle on moonbeam
///      d. sets the emissions manager for staked well
///      e. sets the owner of the moonbeam proxy admin
///      f. sets the owner of the xwell token
contract BreakGlass is Script, Test, BreakGlassCalldata {
    /// @notice addresses contract
    Addresses public addresses;

    function run() public {
        addresses = new Addresses();
        bytes memory data = buildWhitelistedCalldatas(addresses);
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        vm.prank(addresses.getAddress("BREAK_GLASS_GUARDIAN"));
        (bool success, bytes memory errorMessage) = governor.call{value: 0}(
            data
        );

        require(success, string(errorMessage));
    }
}

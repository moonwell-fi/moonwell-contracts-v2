pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {mipm23c} from "@proposals/mips/mip-m23/mip-m23c.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

/// Performs the following actions which hand off direct or pending ownership
/// of the contracts from the Multichain Governor to the Artemis Timelock contract:
///    1. calls executeBreakGlass on the governor, which:
///      a. calls set trusted sender on temporal governor through wormhole core
///      b. calls set pending admin of all mTokens on moonbeam
///      c. sets the admin of chainlink oracle on moonbeam
///      d. sets the emissions manager for staked well
///      e. sets the owner of the moonbeam proxy admin
///      f. sets the owner of the xwell token
contract BreakGlass is Script, mipm23c {
    /// @notice addresses contract
    Addresses public addresses;

    struct Calls {
        address target;
        bytes call;
    }

    function run() public override {
        /// ensure script runs on moonbeam
        vm.selectFork(moonbeamForkId);

        addresses = new Addresses();
        buildCalldata(addresses);
        bytes memory data = getCalldata();
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        console.log("Break Glass Calldata");
        console.logBytes(data);

        vm.prank(addresses.getAddress("BREAK_GLASS_GUARDIAN"));
        (bool success, bytes memory errorMessage) = governor.call{value: 0}(
            data
        );

        require(success, string(errorMessage));
    }

    function getCalldata() public view returns (bytes memory) {
        Calls[] memory calls = new Calls[](17);

        calls[0] = Calls({
            target: addresses.getAddress("mxcUSDC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[1] = Calls({
            target: addresses.getAddress("mUSDCwh"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[2] = Calls({
            target: addresses.getAddress("mFRAX"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[3] = Calls({
            target: addresses.getAddress("mxcUSDT"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[4] = Calls({
            target: addresses.getAddress("mxcDOT"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[5] = Calls({
            target: addresses.getAddress("MNATIVE"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[6] = Calls({
            target: addresses.getAddress("MOONWELL_mUSDC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[7] = Calls({
            target: addresses.getAddress("DEPRECATED_MOONWELL_mETH"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[8] = Calls({
            target: addresses.getAddress("MOONWELL_mBUSD"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[9] = Calls({
            target: addresses.getAddress("DEPRECATED_MOONWELL_mWBTC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[10] = Calls({
            target: addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[11] = Calls({
            target: addresses.getAddress("UNITROLLER"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        calls[12] = Calls({
            target: addresses.getAddress("STKNATIVE"),
            call: approvedCalldata[3] /// setEmissionsManager
        });

        calls[13] = Calls({
            target: addresses.getAddress("CHAINLINK_ORACLE"),
            call: approvedCalldata[2] /// setAdmin
        });

        calls[14] = Calls({
            target: addresses.getAddress("xWELL_PROXY"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[15] = Calls({
            target: addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[16] = Calls({
            target: addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            call: approvedCalldata[5] /// transferOwnership
        });

        calls[17] = Calls({
            target: addresses.getAddress("MOONWELL_mWBTC"),
            call: approvedCalldata[1] /// _setPendingAdmin
        });

        address[] memory targets = new address[](calls.length);
        bytes[] memory callDatas = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            targets[i] = calls[i].target;
            callDatas[i] = calls[i].call;
        }

        return
            abi.encodeWithSignature(
                "executeBreakGlass(address[],bytes[])",
                targets,
                callDatas
            );
    }
}

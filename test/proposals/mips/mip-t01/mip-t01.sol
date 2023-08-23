//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {TimelockProposal} from "@test/proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {ChainlinkOracle} from "@protocol/Oracles/ChainlinkOracle.sol";

/// This MIP sets the price feeds for wstETH and cbETH.
contract mipt01 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIPT01";

    constructor() {
        _setNonce(2);
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        /// -------------- FEED CONFIGURATION --------------

        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        address wstETHFeed = addresses.getAddress("stETHETH_ORACLE");
        address cbETHFeed = addresses.getAddress("cbETHETH_ORACLE");

        unchecked {
            _pushCrossChainAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    "wstETH",
                    wstETHFeed
                ),
                "Temporal governor sets feed on wstETH market"
            );

            _pushCrossChainAction(
                chainlinkOracle,
                abi.encodeWithSignature(
                    "setFeed(string,address)",
                    "cbETH",
                    cbETHFeed
                ),
                "Temporal governor sets feed on cbETH market"
            );
        }
    }

    function run(Addresses addresses, address) public override {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that all the configurations are correctly set
    /// @dev this function is called after the proposal is executed to
    /// validate that all state transitions worked correctly
    function validate(Addresses addresses, address) public override {
        address chainlinkOracleAddress = addresses.getAddress("CHAINLINK_ORACLE");
        address wstETHFeed = addresses.getAddress("stETHETH_ORACLE");
        address cbETHFeed = addresses.getAddress("cbETHETH_ORACLE");

        unchecked {
            ChainlinkOracle chainlinkOracle = ChainlinkOracle(
                chainlinkOracleAddress
            );
                
            assertEq(
                chainlinkOracle.getFeed("wstETH"),
                address(wstETHFeed)
            );

            assertEq(
                chainlinkOracle.getFeed("cbETH"),
                address(cbETHFeed)
            );
        }
    }
}

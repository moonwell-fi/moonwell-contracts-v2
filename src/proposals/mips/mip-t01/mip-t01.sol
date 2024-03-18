//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TimelockProposal} from "@proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";

/// This MIP sets the price feeds for wstETH and cbETH.
contract mipt01 is Proposal, CrossChainProposal, Configs {
    string public constant name = "mip-t01";

    constructor() {
        string memory descriptionPath = string(
            abi.encodePacked("proposals/mips/", name, "/", name, ".md")
        );
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        /// -------------- FEED CONFIGURATION --------------

        address chainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        address wstETHFeed = addresses.getAddress("stETHETH_ORACLE");
        address cbETHFeed = addresses.getAddress("cbETHETH_ORACLE");

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

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that all the configurations are correctly set
    /// @dev this function is called after the proposal is executed to
    /// validate that all state transitions worked correctly
    function validate(Addresses addresses, address) public override {
        address chainlinkOracleAddress = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );
        address wstETHFeed = addresses.getAddress("stETHETH_ORACLE");
        address cbETHFeed = addresses.getAddress("cbETHETH_ORACLE");

        ChainlinkOracle chainlinkOracle = ChainlinkOracle(
            chainlinkOracleAddress
        );

        assertEq(
            address(chainlinkOracle.getFeed("wstETH")),
            address(wstETHFeed)
        );

        assertEq(address(chainlinkOracle.getFeed("cbETH")), address(cbETHFeed));
    }
}

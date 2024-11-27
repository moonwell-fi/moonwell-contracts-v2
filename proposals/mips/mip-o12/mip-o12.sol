//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ChainlinkFeedOEVWrapper} from "@protocol/oracles/ChainlinkFeedOEVWrapper.sol";
import {DeployChainlinkOEVWrapper} from "@script/DeployChainlinkOEVWrapper.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipo12 is HybridProposal {
    using ProposalActions for *;

    string public constant override name = "MIP-O12";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-o12/o12.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        DeployChainlinkOEVWrapper deployScript = new DeployChainlinkOEVWrapper();
        deployScript.deployChainlinkOEVWrapper(addresses, "CHAINLINK_ETH_USD");
    }

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setFeed(string,address)",
                ERC20(addresses.getAddress("WETH")).symbol(),
                addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER")
            ),
            "Set price feed for WETH"
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());

        ChainlinkFeedOEVWrapper wrapper = ChainlinkFeedOEVWrapper(
            addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER")
        );

        // Validate owner
        address owner = Ownable(address(wrapper)).owner();
        assertEq(
            owner,
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "Wrong owner"
        );

        // Validate feed address
        assertEq(
            address(wrapper.originalFeed()),
            addresses.getAddress("CHAINLINK_ETH_USD"),
            "Wrong original feed"
        );

        // Validate WETH address
        assertEq(
            address(wrapper.WETH()),
            addresses.getAddress("WETH"),
            "Wrong WETH address"
        );

        // Validate WETH market
        assertEq(
            address(wrapper.WETHMarket()),
            addresses.getAddress("WETH_MARKET"),
            "Wrong WETH market"
        );

        // Validate initial parameters
        assertEq(wrapper.earlyUpdateWindow(), 30, "Wrong early update window"); // Default 30 seconds
        assertEq(wrapper.feeMultiplier(), 99, "Wrong fee multiplier"); // Default 99

        // Validate interface implementation
        assertEq(
            wrapper.decimals(),
            wrapper.originalFeed().decimals(),
            "Wrong decimals"
        );
        assertEq(
            wrapper.description(),
            wrapper.originalFeed().description(),
            "Wrong description"
        );
        assertEq(
            wrapper.version(),
            wrapper.originalFeed().version(),
            "Wrong version"
        );

        // Validate latestRoundData returns original feed data

        (
            uint80 expectedRoundId,
            int256 expectedAnswer,
            uint256 expectedStartedAt,
            uint256 expectedUpdatedAt,
            uint80 expectedAnsweredInRound
        ) = wrapper.originalFeed().latestRoundData();

        (
            uint80 actualRoundId,
            int256 actualAnswer,
            uint256 actualStartedAt,
            uint256 actualUpdatedAt,
            uint80 actualAnsweredInRound
        ) = wrapper.latestRoundData();

        assertEq(actualRoundId, expectedRoundId, "Wrong roundId");
        assertEq(actualAnswer, expectedAnswer, "Wrong answer");
        assertEq(actualStartedAt, expectedStartedAt, "Wrong startedAt");
        assertEq(actualUpdatedAt, expectedUpdatedAt, "Wrong updatedAt");
        assertEq(
            actualAnsweredInRound,
            expectedAnsweredInRound,
            "Wrong answeredInRound"
        );
    }
}

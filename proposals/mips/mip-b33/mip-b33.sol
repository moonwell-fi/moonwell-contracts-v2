//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MultiRewardDistributor, MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributor.sol";

contract mipb33 is HybridProposal, Configs {
    string public constant override name = "MIP-B33";
    uint256 public constant NEW_USDC_REWARD_SPEED = 13778;
    uint256 public constant NEW_END_TIME = 1731081600;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b33/MIP-B33.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MRD_PROXY"),
            abi.encodeWithSignature(
                "_updateSupplySpeed(address,address,uint256)",
                addresses.getAddress("MOONWELL_USDC"),
                addresses.getAddress("USDC"),
                NEW_USDC_REWARD_SPEED
            ),
            "Set supply side USDC emissions for Moonwell USDC"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY"),
            abi.encodeWithSignature(
                "_updateBorrowSpeed(address,address,uint256)",
                addresses.getAddress("MOONWELL_USDC"),
                addresses.getAddress("USDC"),
                NEW_USDC_REWARD_SPEED
            ),
            "Set borrow USDC emissions for Moonwell USDC"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY"),
            abi.encodeWithSignature(
                "_updateEndTime(address,address,uint256)",
                addresses.getAddress("MOONWELL_USDC"),
                addresses.getAddress("USDC"),
                NEW_END_TIME
            ),
            "Set USDC emission end time for Moonwell USDC"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY"),
            abi.encodeWithSignature(
                "_updateOwner(address,address,address)",
                addresses.getAddress("MOONWELL_USDC"),
                addresses.getAddress("USDC"),
                addresses.getAddress("GAUNTLET_MULTISIG")
            ),
            "Set Gauntlet as the owner of USDC emissions for Moonwell USDC"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        MultiRewardDistributorCommon.MarketConfig
            memory marketConfig = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            ).getConfigForMarket(
                    MToken(addresses.getAddress("MOONWELL_USDC")),
                    addresses.getAddress("USDC")
                );

        assertEq(
            marketConfig.supplyEmissionsPerSec,
            NEW_USDC_REWARD_SPEED,
            "Supply speed not set correctly"
        );
        assertEq(
            marketConfig.borrowEmissionsPerSec,
            NEW_USDC_REWARD_SPEED,
            "Borrow speed not set correctly"
        );
        assertEq(
            marketConfig.endTime,
            NEW_END_TIME,
            "End time not set correctly"
        );
        assertEq(
            marketConfig.owner,
            addresses.getAddress("GAUNTLET_MULTISIG"),
            "Owner not set correctly"
        );
    }
}

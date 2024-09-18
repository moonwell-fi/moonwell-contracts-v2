//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

/// DO_PRE_BUILD_MOCK=true DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b31/mip-b31.sol:mipb31
contract mipb31 is HybridProposal, Configs {
    string public constant override name = "MIP-B31";

    uint256 public constant SUPPLY_SIDE_REWARDS = 4538;

    uint256 public constant BORROW_SIDE_REWARDS = 3025;

    uint256 public constant END_TIME = 24994202400;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b31/MIP-B31.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address market = addresses.getAddress("MOONWELL_EURC");
        address mrd = addresses.getAddress("MRD_PROXY");
        address emissionToken = addresses.getAddress("EURC");

        _pushAction(
            mrd,
            abi.encodeWithSignature(
                "_updateSupplySpeed(address,address,uint256)",
                market,
                emissionToken,
                SUPPLY_SIDE_REWARDS
            ),
            string(
                abi.encodePacked(
                    "Set reward supply speed to ",
                    vm.toString(SUPPLY_SIDE_REWARDS),
                    " for ",
                    vm.getLabel(market),
                    " on Base"
                )
            )
        );

        _pushAction(
            mrd,
            abi.encodeWithSignature(
                "_updateBorrowSpeed(address,address,uint256)",
                market,
                emissionToken,
                BORROW_SIDE_REWARDS
            ),
            string(
                abi.encodePacked(
                    "Set reward borrow speed to ",
                    vm.toString(BORROW_SIDE_REWARDS),
                    " for ",
                    vm.getLabel(market),
                    " on Base"
                )
            )
        );

        _pushAction(
            mrd,
            abi.encodeWithSignature(
                "_updateEndTime(address,address,uint256)",
                market,
                emissionToken,
                END_TIME
            ),
            string(
                abi.encodePacked(
                    "Set reward end time to ",
                    vm.toString(END_TIME),
                    " for ",
                    vm.getLabel(market),
                    " on Base"
                )
            )
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        address market = addresses.getAddress("MOONWELL_EURC");
        address emissionToken = addresses.getAddress("EURC");
        address mrd = addresses.getAddress("MRD_PROXY");

        MultiRewardDistributorCommon.MarketConfig
            memory config = IMultiRewardDistributor(mrd).getConfigForMarket(
                MToken(market),
                emissionToken
            );

        assertEq(
            config.supplyEmissionsPerSec,
            SUPPLY_SIDE_REWARDS,
            "Supply rewards not set correctly"
        );
        assertEq(
            config.borrowEmissionsPerSec,
            BORROW_SIDE_REWARDS,
            "Borrow rewards not set correctly"
        );
        assertEq(config.endTime, END_TIME, "End time not set correctly");
    }
}

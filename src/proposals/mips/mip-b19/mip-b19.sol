//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {ForkID} from "@utils/Enums.sol";

contract mipb19 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B19";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b19/MIP-B19.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Base;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_AERO"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO")
            ),
            "Set interest rate model for Moonwell AERO to updated rate model"
        );
    }

    function run(
        Addresses addresses,
        address
    ) public override(CrossChainProposal, MIPProposal) {
        printCalldata(addresses);
        _simulateCrossChainActions(
            addresses,
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC"),
            addresses.getAddress("MOONWELL_USDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.9e18,
                multiplierPerTimestamp: 0.061e18,
                jumpMultiplierPerTimestamp: 9e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.02e18,
                jumpMultiplierPerTimestamp: 4.2e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO"),
            addresses.getAddress("MOONWELL_AERO"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.145e18,
                jumpMultiplierPerTimestamp: 3.15e18
            })
        );
    }
}

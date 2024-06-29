//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {ForkID} from "@utils/Enums.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b22/mip-b22.sol:mipb22
contract mipb22 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B22";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b22/MIP-B22.md")
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
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbETH")
            ),
            "Set interest rate model for Moonwell cbETH to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_wstETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_wstETH")
            ),
            "Set interest rate model for Moonwell wstETH to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_rETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_rETH")
            ),
            "Set interest rate model for Moonwell rETH to updated rate model"
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

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.01e18,
                jumpMultiplierPerTimestamp: 4.2e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbETH"),
            addresses.getAddress("MOONWELL_cbETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.061e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_wstETH"),
            addresses.getAddress("MOONWELL_wstETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.061e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_rETH"),
            addresses.getAddress("MOONWELL_rETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.061e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO"),
            addresses.getAddress("MOONWELL_AERO"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.18e18,
                jumpMultiplierPerTimestamp: 3.96e18
            })
        );
    }
}

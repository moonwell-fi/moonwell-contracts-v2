//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

contract mipB18 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B18";

    uint256 public constant AERO_NEW_CF = 0.65e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-B18/MIP-B18.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions all happen on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_AERO"),
                AERO_NEW_CF
            ),
            "Set collateral factor for Moonwell AERO to updated collateral factor"
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
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbETH"),
            addresses.getAddress("MOONWELL_cbETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.075e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_wstETH"),
            addresses.getAddress("MOONWELL_wstETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.075e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_rETH"),
            addresses.getAddress("MOONWELL_rETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.35e18,
                multiplierPerTimestamp: 0.075e18,
                jumpMultiplierPerTimestamp: 3.5e18
            })
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_AERO"),
            AERO_NEW_CF
        );
    }
}

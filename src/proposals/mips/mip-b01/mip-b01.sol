//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";

/// This MIP sets the IRM for an MToken contract.
/// It is intended to be used as a template for future MIPs that need to set IRM's.
contract mipb01 is Proposal, CrossChainProposal, Configs {
    string public constant name = "MIP-b01";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    constructor() {
        _setProposalDescription(
            bytes(vm.readFile("./src/proposals/mips/mip-b01/MIP-B01.md"))
        );
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );
    }
    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        JumpRateModel jrm = JumpRateModel(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
        );

        assertEq(
            address(
                MToken(addresses.getAddress("MOONWELL_WETH"))
                    .interestRateModel()
            ),
            address(jrm)
        );

        assertEq(jrm.kink(), 0.75e18, "kink verification failed");
        assertEq(
            jrm.timestampsPerYear(),
            365 days,
            "timestamps per year verifiacation failed"
        );
        assertEq(
            jrm.baseRatePerTimestamp(),
            (0.01e18 * SCALE) / timestampsPerYear / SCALE,
            "base rate per timestamp validation failed"
        );
        assertEq(
            jrm.multiplierPerTimestamp(),
            (0.04e18 * SCALE) / timestampsPerYear / SCALE,
            "multiplier per timestamp validation failed"
        );
        assertEq(
            jrm.jumpMultiplierPerTimestamp(),
            (3.8e18 * SCALE) / timestampsPerYear / SCALE,
            "jump multiplier per timestamp validation failed"
        );
    }
}

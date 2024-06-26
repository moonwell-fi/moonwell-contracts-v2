//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ForkID} from "@utils/Enums.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

contract mipb15 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-b15";

    uint256 public constant USDbC_NEW_RF = 0.20e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b15/MIP-B15.md")
        );
        _setProposalDescription(proposalDescription);
        isArtemisProposal = false;
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Base;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", USDbC_NEW_RF),
            "Set reserve factor for Moonwell USDBC to updated reserve factor"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x0f36Dda2b47984434051AeCAa5F9587DEA7f95B7
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
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
                multiplierPerTimestamp: 0.067e18,
                jumpMultiplierPerTimestamp: 9.0e18
            })
        );

        _validateRF(addresses.getAddress("MOONWELL_USDBC"), USDbC_NEW_RF);
    }
}

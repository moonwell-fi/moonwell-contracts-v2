//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipb32 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B32";
    uint256 public constant USDbC_NEW_RF = 0.75e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b32/MIP-B32.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", USDbC_NEW_RF),
            "Set reserve factor for Moonwell USDbC to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC_MIP_B32")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_cbBTC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbBTC_MIP_B32")
            ),
            "Set interest rate model for Moonwell cbBTC to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateRF(addresses.getAddress("MOONWELL_USDBC"), USDbC_NEW_RF);

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC_MIP_B32"),
            addresses.getAddress("MOONWELL_USDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.9e18,
                multiplierPerTimestamp: 0.05e18,
                jumpMultiplierPerTimestamp: 9e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbBTC_MIP_B32"),
            addresses.getAddress("MOONWELL_cbBTC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.6e18,
                multiplierPerTimestamp: 0.067e18,
                jumpMultiplierPerTimestamp: 3e18
            })
        );
    }
}

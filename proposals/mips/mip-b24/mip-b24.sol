//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipb24 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B24";
    uint256 public constant wstETH_NEW_RF = 0.15e18;
    uint256 public constant rETH_NEW_RF = 0.15e18;
    uint256 public constant cbETH_NEW_RF = 0.15e18;
    uint256 public constant USDC_NEW_RF = 0.1e18;
    uint256 public constant WETH_NEW_RF = 0.15e18;
    uint256 public constant AERO_NEW_RF = 0.3e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b24/MIP-B24.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MOONWELL_wstETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                wstETH_NEW_RF
            ),
            "Set reserve factor for Moonwell wstETH to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_rETH"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", rETH_NEW_RF),
            "Set reserve factor for Moonwell rETH to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", cbETH_NEW_RF),
            "Set reserve factor for Moonwell cbETH to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", USDC_NEW_RF),
            "Set reserve factor for Moonwell USDC to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", WETH_NEW_RF),
            "Set reserve factor for Moonwell WETH to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_AERO"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", AERO_NEW_RF),
            "Set reserve factor for Moonwell AERO to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_AERO"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO_MIP_B24")
            ),
            "Set interest rate model for Moonwell AERO to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateRF(addresses.getAddress("MOONWELL_wstETH"), wstETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_rETH"), rETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_cbETH"), cbETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_USDC"), USDC_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_WETH"), WETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_AERO"), AERO_NEW_RF);

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO_MIP_B24"),
            addresses.getAddress("MOONWELL_AERO"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.23e18,
                jumpMultiplierPerTimestamp: 4.1e18
            })
        );
    }
}

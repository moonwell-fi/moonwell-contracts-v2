//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipb27 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B27";
    uint256 public constant USDbC_NEW_RF = 0.5e18;
    uint256 public constant WETH_NEW_CF = 0.84e18;
    uint256 public constant cbETH_NEW_CF = 0.81e18;
    uint256 public constant wstETH_NEW_CF = 0.81e18;
    uint256 public constant rETH_NEW_CF = 0.81e18;
    uint256 public constant USDbC_NEW_CF = 0.78e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b27/MIP-B27.md")
        );
        _setProposalDescription(proposalDescription);

        //onchainProposalId = 112;
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MOONWELL_wstETH"),
            abi.encodeWithSignature(
                "_setCollateralFactor(uint256)",
                wstETH_NEW_CF
            ),
            "Set collateral factor for Moonwell wstETH to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_rETH"),
            abi.encodeWithSignature(
                "_setCollateralFactor(uint256)",
                rETH_NEW_CF
            ),
            "Set collateral factor for Moonwell rETH to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature(
                "_setCollateralFactor(uint256)",
                cbETH_NEW_CF
            ),
            "Set collateral factor for Moonwell cbETH to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDbC"),
            abi.encodeWithSignature(
                "_setCollateralFactor(uint256)",
                USDbC_NEW_CF
            ),
            "Set collateral factor for Moonwell USDbC to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setCollateralFactor(uint256)",
                WETH_NEW_CF
            ),
            "Set collateral factor for Moonwell WETH to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDbC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", USDbC_NEW_RF),
            "Set reserve factor for Moonwell USDbC to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_AERO"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO_MIP_B27")
            ),
            "Set interest rate model for Moonwell AERO to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC_MIP_B27")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_wstETH"),
            wstETH_NEW_CF
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_rETH"),
            rETH_NEW_CF
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_cbETH"),
            cbETH_NEW_CF
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_USDC"),
            USDbC_NEW_CF
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            WETH_NEW_CF
        );

        _validateRF(addresses.getAddress("MOONWELL_USDbC"), USDbC_NEW_RF);

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_AERO_MIP_B27"),
            addresses.getAddress("MOONWELL_AERO"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.23e18,
                jumpMultiplierPerTimestamp: 5e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC_MIP_B27"),
            addresses.getAddress("MOONWELL_USDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.9e18,
                multiplierPerTimestamp: 0.056e18,
                jumpMultiplierPerTimestamp: 9e18
            })
        );
    }
}

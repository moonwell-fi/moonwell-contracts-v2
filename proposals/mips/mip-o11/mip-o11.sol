//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipo11 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-O11";

    // Define new reserve and collateral factors for various assets
    uint256 public constant WBTC_NEW_RF = 0.6e18;
    uint256 public constant WBTC_NEW_CF = 0.6e18;
    uint256 public constant WETH_NEW_CF = 0.83e18;
    uint256 public constant cbETH_NEW_CF = 0.81e18;
    uint256 public constant wstETH_NEW_CF = 0.81e18;
    uint256 public constant rETH_NEW_CF = 0.81e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-o11/MIP-O11.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {}

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function build(Addresses addresses) public override {
        // Push actions to update Reserve Factors for different assets

        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushAction(
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", WBTC_NEW_RF),
            "Set reserve factor for Moonwell WBTC to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WBTC"),
                WBTC_NEW_CF
            ),
            "Set collateral factor of Moonwell WBTC",
            ActionType.Optimism
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WETH"),
                WETH_NEW_CF
            ),
            "Set collateral factor of Moonwell WETH",
            ActionType.Optimism
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_cbETH"),
                cbETH_NEW_CF
            ),
            "Set collateral factor of Moonwell cbETH",
            ActionType.Optimism
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_wstETH"),
                wstETH_NEW_CF
            ),
            "Set collateral factor of Moonwell wstETH",
            ActionType.Optimism
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_rETH"),
                rETH_NEW_CF
            ),
            "Set collateral factor of Moonwell rETH",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH_MIP_O11")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );
    }

    function validate(Addresses addresses, address) public view override {
        // Validate Collateral Factors

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WBTC"),
            WBTC_NEW_CF
        );

        _validateRF(addresses.getAddress("MOONWELL_WBTC"), WBTC_NEW_RF);

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            WETH_NEW_CF
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_cbETH"),
            cbETH_NEW_CF
        );

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

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH_MIP_O11"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.9e18,
                multiplierPerTimestamp: 0.01e18,
                jumpMultiplierPerTimestamp: 8e18
            })
        );
    }
}

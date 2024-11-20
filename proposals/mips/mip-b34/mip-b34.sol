//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipb34 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B34";
    uint256 public constant USDbC_NEW_RF = 0.9e18;
    uint256 public constant USDbC_NEW_CF = 0.76e18;
    uint256 public constant DAI_NEW_RF = 0.4e18;
    uint256 public constant DAI_NEW_CF = 0.8e18;
    uint256 public constant WETH_NEW_RF = 0.05e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b34/MIP-B34.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", USDbC_NEW_RF),
            "Set reserve factor for Moonwell USDbC to updated reserve factor"
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_USDBC"),
                USDbC_NEW_CF
            ),
            "Set collateral factor for Moonwell USDbC to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", DAI_NEW_RF),
            "Set reserve factor for Moonwell DAI to updated reserve factor"
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_DAI"),
                DAI_NEW_CF
            ),
            "Set collateral factor for Moonwell DAI to updated collateral factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", WETH_NEW_RF),
            "Set reserve factor for Moonwell WETH to updated reserve factor"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI_MIP_B34")
            ),
            "Set interest rate model for Moonwell USDbC to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI_MIP_B34")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH_MIP_B34")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        _validateRF(addresses.getAddress("MOONWELL_USDBC"), USDbC_NEW_RF);
        _validateRF(addresses.getAddress("MOONWELL_DAI"), DAI_NEW_RF);
        _validateRF(addresses.getAddress("MOONWELL_WETH"), WETH_NEW_RF);

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_USDBC"),
            USDbC_NEW_CF
        );
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_DAI"),
            DAI_NEW_CF
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI_MIP_B34"),
            addresses.getAddress("MOONWELL_USDBC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.6e18,
                multiplierPerTimestamp: 0.04e18,
                jumpMultiplierPerTimestamp: 4e18
            })
        );
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI_MIP_B34"),
            addresses.getAddress("MOONWELL_DAI"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.6e18,
                multiplierPerTimestamp: 0.04e18,
                jumpMultiplierPerTimestamp: 4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH_MIP_B34"),
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

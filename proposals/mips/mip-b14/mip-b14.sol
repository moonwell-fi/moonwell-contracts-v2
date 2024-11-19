//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipb14 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B14";

    uint256 public constant wstETH_NEW_RF = 0.3e18;
    uint256 public constant rETH_NEW_RF = 0.3e18;
    uint256 public constant cbETH_NEW_RF = 0.3e18;
    uint256 public constant DAI_NEW_RF = 0.2e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b14/mip-b14.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI_MIP_B14")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH_MIP_B14")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );

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
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature("_setReserveFactor(uint256)", DAI_NEW_RF),
            "Set reserve factor for Moonwell DAI to updated reserve factor"
        );
    }

    function teardown(Addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI"),
            addresses.getAddress("MOONWELL_DAI"),
            IRParams({
                kink: 0.75e18,
                baseRatePerTimestamp: 0,
                multiplierPerTimestamp: 0.067e18,
                jumpMultiplierPerTimestamp: 9.0e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                kink: 0.8e18,
                baseRatePerTimestamp: 0,
                multiplierPerTimestamp: 0.032e18,
                jumpMultiplierPerTimestamp: 4.2e18
            })
        );

        _validateRF(addresses.getAddress("MOONWELL_wstETH"), wstETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_rETH"), rETH_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_DAI"), DAI_NEW_RF);

        _validateRF(addresses.getAddress("MOONWELL_cbETH"), cbETH_NEW_RF);
    }
}

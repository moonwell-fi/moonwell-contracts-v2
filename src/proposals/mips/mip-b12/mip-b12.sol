//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";

contract mipb12 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B12";

    uint256 public constant wstETH_NEW_CF = 0.77e18;
    uint256 public constant rETH_NEW_CF = 0.77e18;
    uint256 public constant cbETH_NEW_CF = 0.77e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b12/MIP-B12.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 67;
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_wstETH"),
                wstETH_NEW_CF
            ),
            "Set collateral factor for Moonwell wstETH to updated collateral factor"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_rETH"),
                rETH_NEW_CF
            ),
            "Set collateral factor for Moonwell rETH to updated collateral factor"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_cbETH"),
                cbETH_NEW_CF
            ),
            "Set collateral factor for Moonwell cbETH to updated collateral factor"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_CBETH_MIP_B12")
            ),
            "Set interest rate model for Moonwell cbETH to updated rate model"
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

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbETH"),
            addresses.getAddress("MOONWELL_cbETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.06e18,
                jumpMultiplierPerTimestamp: 3.15e18
            })
        );
    }
}

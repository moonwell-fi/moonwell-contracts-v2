//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";

contract mipo08 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-O08";

    // Define new reserve and collateral factors for various assets
    uint256 public constant NEW_WBTC_RESERVE_FACTOR = 0.3e18;
    uint256 public constant NEW_WBTC_COLLATERAL_FACTOR = 0.79e18;

    uint256 public constant BASE_RATE = 0;
    uint256 public constant KINK = 0.9e18;
    uint256 public constant MULTIPLIER = 0.056e18;
    uint256 public constant JUMP_MULTIPLIER = 5e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-o08/MIP-O08.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {
        address irModel = address(
            new JumpRateModel(BASE_RATE, MULTIPLIER, JUMP_MULTIPLIER, KINK)
        );

        addresses.addAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08", irModel);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function build(Addresses addresses) public override {
        // Push actions to update Reserve Factors for different assets

        _pushAction(
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_WBTC_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell WBTC to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WBTC"),
                NEW_WBTC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell WBTC",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDT"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08")
            ),
            "Set interest rate model for Moonwell USDT to updated rate model"
        );

        _pushAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );
    }

    function validate(Addresses addresses, address) public view override {
        // Validate Collateral Factors

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WBTC"),
            NEW_WBTC_COLLATERAL_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_WBTC"),
            NEW_WBTC_RESERVE_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08"),
            addresses.getAddress("MOONWELL_USDC"),
            IRParams({
                baseRatePerTimestamp: BASE_RATE,
                kink: KINK,
                multiplierPerTimestamp: MULTIPLIER,
                jumpMultiplierPerTimestamp: JUMP_MULTIPLIER
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08"),
            addresses.getAddress("MOONWELL_USDT"),
            IRParams({
                baseRatePerTimestamp: BASE_RATE,
                kink: KINK,
                multiplierPerTimestamp: MULTIPLIER,
                jumpMultiplierPerTimestamp: JUMP_MULTIPLIER
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_MIP_O08"),
            addresses.getAddress("MOONWELL_DAI"),
            IRParams({
                baseRatePerTimestamp: BASE_RATE,
                kink: KINK,
                multiplierPerTimestamp: MULTIPLIER,
                jumpMultiplierPerTimestamp: JUMP_MULTIPLIER
            })
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// proposals/mips/mip-m33/mip-m33.sol:mipm33
contract mipm38 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M38";

    uint256 public constant NEW_M_WBTCWH_COLLATERAL_FACTOR = 0.28e18;
    uint256 public constant NEW_M_USDCWH_COLLATERAL_FACTOR = 0.51e18;
    uint256 public constant NEW_M_WETHWH_COLLATERAL_FACTOR = 0.45e18;
    uint256 public constant NEW_M_FRAX_COLLATERAL_FACTOR = 0.55e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-m38/MIP-M38.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        etch(vm, addresses);
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mWBTC"),
                NEW_M_WBTCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mWBTC",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mETH"),
                NEW_M_WETHWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mETH",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mUSDCwh"),
                NEW_M_USDCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mUSDCwh",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mFRAX"),
                NEW_M_FRAX_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mFRAX",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mUSDCwh_MIP_M38")
            ),
            "Set interest rate model for mUSDCwh to updated rate model",
            ActionType.Moonbeam
        );
        _pushAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mFRAX_MIP_M38")
            ),
            "Set interest rate model for mFRAX to updated rate model",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M38: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) > 1,
            "MIP-M38: should have moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mWBTC"),
            NEW_M_WBTCWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("mUSDCwh"),
            NEW_M_USDCWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mETH"),
            NEW_M_WETHWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mFRAX"),
            NEW_M_FRAX_COLLATERAL_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mUSDCwh_MIP_M38"),
            addresses.getAddress("mUSDCwh"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mFRAX_MIP_M38"),
            addresses.getAddress("MOONWELL_mFRAX"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );
    }
}

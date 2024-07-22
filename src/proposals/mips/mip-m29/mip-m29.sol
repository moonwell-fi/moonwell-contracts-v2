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
/// src/proposals/mips/mip-m27/mip-m27.sol:mipm27
contract mipm29 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M29";

    uint256 public constant NEW_MGLIMMER_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_MXC_DOT_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_M_ETHWH_RESERVE_FACTOR = 0.35e18;

    uint256 public constant NEW_M_ETHWH_COLLATERAL_FACTOR = 0.48e18;
    uint256 public constant NEW_M_USDCWH_COLLATERAL_FACTOR = 0.58e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m29/MIP-M29.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 15;
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
            addresses.getAddress("mGLIMMER"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MGLIMMER_RESERVE_FACTOR
            ),
            "Set reserve factor for mGLIMMER to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcDOT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_DOT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcDOT to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mETHwh"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_M_ETHWH_RESERVE_FACTOR
            ),
            "Set reserve factor for mETHwh to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mETHwh"),
                NEW_M_ETHWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mETHwh",
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
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mxcUSDC")
            ),
            "Set interest rate model for mxcUSDC to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mxcUSDT")
            ),
            "Set interest rate model for mxcUSDT to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mFRAX")
            ),
            "Set interest rate model for mFRAX to updated rate model",
            ActionType.Moonbeam
        );

        // Adding transferFrom actions
        _pushAction(
            addresses.getAddress("WELL"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451,
                0x7793E08Eb4525309C46C9BA394cE33361A167ba4,
                6778847000000000000000000
            ),
            "Transfer 6778847 WELL from 0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451 to 0x7793E08Eb4525309C46C9BA394cE33361A167ba4",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("WELL"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451,
                0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180,
                6923077000000000000000000
            ),
            "Transfer 6923077 WELL from 0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451 to 0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M29: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateRF(
            addresses.getAddress("mGLIMMER"),
            NEW_MGLIMMER_RESERVE_FACTOR
        );

        _validateRF(addresses.getAddress("mxcDOT"), NEW_MXC_DOT_RESERVE_FACTOR);

        _validateRF(addresses.getAddress("mETHwh"), NEW_M_ETHWH_RESERVE_FACTOR);

        _validateCF(
            addresses,
            addresses.getAddress("mETHwh"),
            NEW_M_ETHWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("mUSDCwh"),
            NEW_M_USDCWH_COLLATERAL_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDC"),
            addresses.getAddress("mxcUSDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDT"),
            addresses.getAddress("mxcUSDT"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mFRAX"),
            addresses.getAddress("mFRAX"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.08e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );
    }
}

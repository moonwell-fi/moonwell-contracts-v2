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
/// src/proposals/mips/mip-m39/mip-m39.sol:mipm39
contract mipm39 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M39";

    uint256 public constant NEW_M_WBTCWH_COLLATERAL_FACTOR = 0.25e18;
    uint256 public constant NEW_M_USDCWH_COLLATERAL_FACTOR = 0.50e18;
    uint256 public constant NEW_M_WETHWH_COLLATERAL_FACTOR = 0.43e18;
    uint256 public constant NEW_M_XCUSDC_COLLATERAL_FACTOR = 0.6e18;
    uint256 public constant NEW_M_WBTCWH_RESERVE_FACTOR = 0.4e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m39/MIP-M39.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        etch(vm, addresses);
    }

    function deploy(Addresses addresses, address) public override {}

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
                addresses.getAddress("mxcUSDC"),
                NEW_M_XCUSDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mxcUSDC",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_M_WBTCWH_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell WBTC to updated reserve factor"
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M39: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) > 1,
            "MIP-M39: should have moonbeam actions"
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
            addresses.getAddress("mxcUSDC"),
            NEW_M_XCUSDC_COLLATERAL_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_mWBTC"),
            NEW_M_WBTCWH_RESERVE_FACTOR
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID, MOONBASE_CHAIN_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m40/mip-m40.sol:mipm40
contract mipm40 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M40";

    uint256 public constant WBTCWH_NEW_CF = 0.2e18;
    uint256 public constant WBTCWH_NEW_RF = 0.6e18;
    uint256 public constant USDCWH_NEW_CF = 0.45e18;
    uint256 public constant WETHWH_NEW_CF = 0.41e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m40/MIP-M40.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        if (block.chainid != MOONBASE_CHAIN_ID) {
            etch(vm, addresses);
        }
    }

    function deploy(Addresses addresses, address) public override {}

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mWBTC"),
                WBTCWH_NEW_CF
            ),
            "Set collateral factor of MOONWELL_mWBTC",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                WBTCWH_NEW_RF
            ),
            "Set reserve factor for Moonwell WBTC to updated reserve factor"
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mETH"),
                WETHWH_NEW_CF
            ),
            "Set collateral factor of MOONWELL_mETH",
            ActionType.Moonbeam
        );

        _pushAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mUSDCwh"),
                USDCWH_NEW_CF
            ),
            "Set collateral factor of mUSDCwh",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M40: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) > 1,
            "MIP-M40: should have moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mWBTC"),
            WBTCWH_NEW_CF
        );

        _validateRF(addresses.getAddress("MOONWELL_mWBTC"), WBTCWH_NEW_RF);

        _validateCF(addresses, addresses.getAddress("mUSDCwh"), USDCWH_NEW_CF);

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mETH"),
            WETHWH_NEW_CF
        );
    }
}

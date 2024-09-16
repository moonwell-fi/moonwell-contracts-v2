//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract testnet is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M25";

    uint256 public constant NEW_USDC_COLLATERAL_FACTOR = 0.25e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m25/MIP-M25.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mUSDC"),
                NEW_USDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mxcUSDC",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mUSDC"),
            NEW_USDC_COLLATERAL_FACTOR
        );
    }
}

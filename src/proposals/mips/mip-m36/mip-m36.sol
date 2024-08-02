//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipm36 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M36";

    uint256 public constant NEW_MFRAX_RESERVE_FACTOR = 0.3e18;
    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m36/MIP-M36.md")
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
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MFRAX_RESERVE_FACTOR
            ),
            "Set reserve factor for mFRAX to updated reserve factor",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M36: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 1,
            "MIP-M36: should have moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateRF(addresses.getAddress("mFRAX"), NEW_MFRAX_RESERVE_FACTOR);
    }
}

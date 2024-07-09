//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {
    ActionType,
    HybridProposal
} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m33/mip-m33.sol:mipm33
contract mipm33 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M33";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m33/MIP-M33.md")
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
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mWBTCwh")
            ),
            "Set interest rate model for mWBTCwh to updated rate model",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M33: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 1,
            "MIP-M33: should have moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mWBTCwh"),
            addresses.getAddress("MOONWELL_mWBTC"),
            IRParams({
                baseRatePerTimestamp: 0.02e18,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.187e18,
                jumpMultiplierPerTimestamp: 3e18
            })
        );
    }
}

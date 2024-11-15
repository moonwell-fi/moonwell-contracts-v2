//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract mipx05 is HybridProposal {
    string public constant override name = "MIP-X05";

    uint256 public constant COOLDOWN_SECONDS = 7 days;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-x05/x05.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("STK_GOVTOKEN_PROXY", BASE_CHAIN_ID),
            abi.encodeWithSignature(
                "setCoolDownSeconds(uint256)",
                COOLDOWN_SECONDS
            ),
            "Set the cooldown period for stkWELL on Base",
            ActionType.Base
        );

        _pushAction(
            addresses.getAddress("STK_GOVTOKEN_PROXY", OPTIMISM_CHAIN_ID),
            abi.encodeWithSignature(
                "setCoolDownSeconds(uint256)",
                COOLDOWN_SECONDS
            ),
            "Set the cooldown period for stkWELL on Optimism",
            ActionType.Optimism
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(OPTIMISM_FORK_ID);

        IStakedWell stakedWellOptimism = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        vm.assertEq(
            stakedWellOptimism.COOLDOWN_SECONDS(),
            COOLDOWN_SECONDS,
            "Optimism cooldown period not set correctly"
        );

        vm.selectFork(BASE_FORK_ID);

        IStakedWell stakedWellBase = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        vm.assertEq(
            stakedWellBase.COOLDOWN_SECONDS(),
            COOLDOWN_SECONDS,
            "Base cooldown period not set correctly"
        );
    }
}

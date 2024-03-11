//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

//- Move temporal governor ownership back to artemis
//- Move bridge adapter ownership back to artemis
//- Move xwell ownership back to artemis
//- Move distributor ownership back to artemis
//- Remove old governor as a trusted sender on temporal governor
contract Proposal2 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18E";

    constructor() {
        _setProposalDescription(
            bytes("Transfer lending system Moonbase ownership")
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        vm.selectFork(baseForkId);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
    }

    function validate(Addresses addresses, address) public override {}
}

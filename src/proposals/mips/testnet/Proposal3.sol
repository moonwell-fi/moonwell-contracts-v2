//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to initialize the Multichain Governor contract
/// After this proposal, the Temporal Governor will have 2 admins, the
/// Multichain Governor and the Artemis Timelock
/// update MULTICHAIN_GOVERNOR_PROXY to 0x716ff5a3Acbcd6cA05e921a524b80B5B68FAca05 in Addresses.json for moonbase
/// Command:
///      MOONBEAM_RPC_URL="https://rpc.api.moonbase.moonbeam.network" forge script src/proposals/mips/mip-m18/mip-updatecrosschainperiod.sol --fork-url moonbase -vvvv
contract Proposal3 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP_UPDATE_CROSS_CHAIN_PERIOD";

    uint256 public constant crossChainPeriod = 1 hours;
    // min voting period is 10 minutes
    uint256 public constant votingPeriod = 1 hours;

    constructor() {
        bytes memory proposalDescription = bytes("Update cross chain period");
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        vm.selectFork(moonbeamForkId);

        _pushHybridAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "updateCrossChainVoteCollectionPeriod(uint256)",
                crossChainPeriod
            ),
            "Update cross chain period",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "updateVotingPeriod(uint256)",
                votingPeriod
            ),
            "Update voting period",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(moonbeamForkId);
    }

    function validate(Addresses addresses, address) public override {
        assertEq(
            MultichainGovernor(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
            ).crossChainVoteCollectionPeriod(),
            crossChainPeriod,
            "Cross chain period not updated"
        );

        assertEq(
            MultichainGovernor(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
            ).votingPeriod(),
            votingPeriod,
            "Voting period not updated"
        );
    }
}

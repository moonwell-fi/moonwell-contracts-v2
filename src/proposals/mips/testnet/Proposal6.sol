//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

// Transfer proxy admin ownership from the current governor to the timelock
contract Proposal6 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "PROPOSAL_6";

    constructor() {
        _setProposalDescription(
            bytes(
                "Transfer proxy admin ownership from the current governor to the timelock"
            )
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        address timelock = addresses.getAddress(
            "MOONBEAM_TIMELOCK",
            moonBaseChainId
        );

        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        _pushHybridAction(
            proxyAdmin,
            abi.encodeWithSignature("transferOwnership(address)", timelock),
            "Set the owner of the Proxy Admin to Timelock",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        _runMoonbeamMultichainGovernor(addresses, address(1000000));
    }

    function validate(Addresses addresses, address) public override {
        assertEq(
            Ownable(addresses.getAddress("MOONBEAM_PROXY_ADMIN")).owner(),
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            "MOONBEAM_PROXY_ADMIN owner incorrect"
        );
    }
}

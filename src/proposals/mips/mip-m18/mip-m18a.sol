//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to create the Multichain Governor contract
contract mipm18a is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18A";

    function deploy(Addresses addresses, address) public override {
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY", governorProxy);
        addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl);
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
    }

    function validate(Addresses addresses, address) public override {
        /// TODO validate that pending owners have been set where appropriate
        /// TODO validate that new admin/owner has been set where appropriate
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

contract mipm30 is Configs, GovernanceProposal, ParameterValidation {
    string public constant override name = "MIP-M30";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m30/MIP-M30.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function afterDeploySetup(Addresses) public override {}

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        /// set pending admin of mWBTCwh to the Multichain Governor
        _pushGovernanceAction(
            addresses.getAddress("mWBTCwh"),
            "Set the pending admin of the new wBTC market to the Multichain Governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );
    }

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
        setDebug(true);

        _simulateGovernanceActions(
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            address(this)
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        assertEq(
            Timelock(addresses.getAddress("mWBTCwh")).pendingAdmin(),
            governor,
            "mWBTCwh pending admin incorrect"
        );
    }
}
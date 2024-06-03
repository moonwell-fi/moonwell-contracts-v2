//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";

import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {mipm30} from "@proposals/mips/mip-m30/mip-m30.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";

contract mipm31 is Configs, HybridProposal {
    string public constant override name = "MIP-M30";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m31/MIP-M31.md")
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

    function teardown(Addresses addresses, address caller) public override {
        // we must run first mip-m30 to set the pending admin of mWBTCwh to the Multichain Governor
        IProposal mip30 = IProposal(address(new mipm30()));
        mip30.build(addresses);
        mip30.run(addresses, caller);
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        /// accept admin of mWBTCwh to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("mWBTCwh"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept the admin transfer of the new wBTC market to the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-M27: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        assertEq(
            Timelock(addresses.getAddress("mWBTCwh")).admin(),
            governor,
            "mWBTCwh admin incorrect"
        );
    }
}

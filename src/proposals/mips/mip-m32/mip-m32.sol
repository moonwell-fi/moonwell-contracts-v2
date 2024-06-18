//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";

import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {mipm30} from "@proposals/mips/mip-m30/mip-m30.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";

import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

contract mipm32 is Configs, HybridProposal, ParameterValidation {
    string public constant override name = "MIP-M30";

    uint256 public constant NEW_M_WBTCWH_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_M_WBTCWH_COLLATERAL_FACTOR = 0.31e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m32/MIP-M32.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public view override returns (ProposalType) {
        return ProposalType.Moonbeam;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function preBuildMock(Addresses) public override {}

    function teardown(Addresses addresses, address caller) public override {
        // we must run first mip-m30 to set the pending admin of MOONWELL_mWBTC to the Multichain Governor
        IProposal mip30 = IProposal(address(new mipm30()));
        mip30.build(addresses);
        mip30.run(addresses, caller);
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        /// accept admin of MOONWELL_mWBTC to the Multichain Governor
        _pushHybridAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept the admin transfer of the new wBTC market to the Multichain Governor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_M_WBTCWH_RESERVE_FACTOR
            ),
            "Set reserve factor for MOONWELL_mWBTC to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mWBTC"),
                NEW_M_WBTCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mWBTC",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-M31: should have no base actions"
        );

        require(
            moonbeamActions.length == 3,
            "MIP-M31: should have 3 moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        assertEq(
            Timelock(addresses.getAddress("MOONWELL_mWBTC")).admin(),
            governor,
            "MOONWELL_mWBTC admin incorrect"
        );

        _validateRF(
            addresses.getAddress("MOONWELL_mWBTC"),
            NEW_M_WBTCWH_RESERVE_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mWBTC"),
            NEW_M_WBTCWH_COLLATERAL_FACTOR
        );
    }
}

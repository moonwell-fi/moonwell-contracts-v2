//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {mipm30} from "@proposals/mips/mip-m30/mip-m30.sol";
import {Configs} from "@proposals/Configs.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipm32 is Configs, HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M32";

    uint256 public constant NEW_M_WBTCWH_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_M_WBTCWH_COLLATERAL_FACTOR = 0.31e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m32/MIP-M32.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 20;
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
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
        _pushAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature("_acceptAdmin()"),
            "Accept the admin transfer of the new wBTC market to the Multichain Governor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_M_WBTCWH_RESERVE_FACTOR
            ),
            "Set reserve factor for MOONWELL_mWBTC to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mWBTC"),
                NEW_M_WBTCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mWBTC",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M31: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 3,
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

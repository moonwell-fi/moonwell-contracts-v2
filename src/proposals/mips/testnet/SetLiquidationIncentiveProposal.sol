//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";

contract SetLiquidationIncentiveProposal is HybridProposal {
    string public constant name = "SetLiquidationIncentiveProposal";

    uint256 public constant liquidityIncentive = 120e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            "Set the liquidation incentive to ",
            abi.encodePacked(liquidityIncentive)
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress(
                "UNITROLLER",
                sendingChainIdToReceivingChainId[block.chainid]
            ),
            abi.encodeWithSignature(
                "_setLiquidationIncentive(uint256)",
                liquidityIncentive
            ),
            "Set liquidation incentive",
            false
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(moonbeamForkId);
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        assertEq(
            Comptroller(addresses.getAddress("UNITROLLER"))
                .liquidationIncentiveMantissa(),
            liquidityIncentive,
            "Liquidation incentive not set correctly"
        );

        vm.selectFork(moonbeamForkId);
    }
}

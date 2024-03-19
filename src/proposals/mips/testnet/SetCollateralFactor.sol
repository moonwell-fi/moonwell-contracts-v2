//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

import {Comptroller} from "@protocol/Comptroller.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";

contract SetCollateralFactorProposal is HybridProposal {
    string public constant name = "SetCollateralFactorProposal";

    uint256 public constant collateralFactor = 0.6e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            "Set collateral factor"
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
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WETH"),
                collateralFactor
            ),
            "Set collateral factor",
            false
        );

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress(
                    "MOONWELL_WETH",
                    sendingChainIdToReceivingChainId[block.chainid]
                ),
                collateralFactor
            ),
            "Set collateral factor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        // switch back to the moonbeam fork so we can run the validations
        vm.selectFork(moonbeamForkId);
    }

    function validate(Addresses addresses, address) public override {
        (, uint256 collateralFactorMoonbase) = Comptroller(
            addresses.getAddress("UNITROLLER")
        ).markets(addresses.getAddress("MOONWELL_WETH"));

        assertEq(
            collateralFactorMoonbase,
            collateralFactor,
            "Collateral factor not set correctly on moonbase"
        );

        vm.selectFork(baseForkId);

        (, uint256 collateralFactorBase) = Comptroller(
            addresses.getAddress("UNITROLLER")
        ).markets(addresses.getAddress("MOONWELL_WETH"));

        assertEq(
            collateralFactorBase,
            collateralFactor,
            "Collateral factor not set correctly on base"
        );

        vm.selectFork(moonbeamForkId);
    }
}

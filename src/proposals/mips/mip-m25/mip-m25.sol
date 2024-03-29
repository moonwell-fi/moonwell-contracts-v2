//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {ITokenSaleDistributorProxy} from "../../../tokensale/ITokenSaleDistributorProxy.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m25/mip-m25.sol:mipm25
contract mipm25 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M25";

    /// @notice new mxcUSDC collateral factor
    uint256 public constant MXC_USDC_COLLATERAL_FACTOR = 0.15e18;

    /// @notice new glmr collateral factor
    uint256 public constant MGLIMMER_COLLATERAL_FACTOR = 0.57e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m25/MIP-M25.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions happen only on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mxcUSDC"),
                MXC_USDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mxcUSDC",
            true
        );

        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mGLIMMER"),
                MGLIMMER_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mGLIMMER",
            true
        );

        /// TODO fill out the rest of the proposal
        //// all actions should have their boolean flag to true because they are run on Moonbeam
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-M25: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    /// TODO fill out validations on Moonbeam
    function validate(Addresses addresses, address) public override {}
}

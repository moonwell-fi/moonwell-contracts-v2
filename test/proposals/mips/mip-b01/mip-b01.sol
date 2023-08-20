//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/IRModels/JumpRateModel.sol";
import {TimelockProposal} from "@test/proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

/// This MIP sets the reward speeds for different markets in the MultiRewardDistributor
/// contract. It is intended to be used as a template for future MIPs that need to set reward speeds.
/// The first step is to open `mainnetRewardStreams.json` and add the reward streams for the
/// different mTokens. Then generate calldata by adding MIP01 to the TestProposals file.
contract mipb01 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIP-b01";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    constructor() {
        _setNonce(2);
    }

    function deploy(Addresses addresses, address) public {}

    function afterDeploy(Addresses addresses, address) public {}

    function afterDeploySetup(Addresses addresses) public {}

    function build(Addresses addresses) public {
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );
    }

    function run(Addresses addresses, address) public {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public {
        JumpRateModel jrm = JumpRateModel(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
        );

        assertEq(
            address(
                MToken(addresses.getAddress("MOONWELL_WETH"))
                    .interestRateModel()
            ),
            address(jrm)
        );

        assertEq(jrm.kink(), 0.75e18, "kink verification failed");
        assertEq(
            jrm.timestampsPerYear(),
            365 days,
            "timestamps per year verifiacation failed"
        );
        assertEq(
            jrm.baseRatePerTimestamp(),
            (0.01e18 * SCALE) / timestampsPerYear / SCALE,
            "base rate per timestamp validation failed"
        );
        assertEq(
            jrm.multiplierPerTimestamp(),
            (0.04e18 * SCALE) / timestampsPerYear / SCALE,
            "multiplier per timestamp validation failed"
        );
        assertEq(
            jrm.jumpMultiplierPerTimestamp(),
            (3.8e18 * SCALE) / timestampsPerYear / SCALE,
            "jump multiplier per timestamp validation failed"
        );
    }
}

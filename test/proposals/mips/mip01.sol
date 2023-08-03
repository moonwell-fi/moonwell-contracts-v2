//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/core/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {TimelockProposal} from "@test/proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/core/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/core/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

/// This MIP sets the reward speeds for different markets in the MultiRewardDistributor
/// contract. It is intended to be used as a template for future MIPs that need to set reward speeds.
/// The first step is to open `mainnetRewardStreams.json` and add the reward streams for the
/// different mTokens. Then generate calldata by adding MIP01 to the TestProposals file.
contract mip01 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIP01";

    constructor() {
        _setNonce(2);
    }

    function deploy(Addresses addresses, address) public {}

    function afterDeploy(Addresses addresses, address) public {}

    function build(Addresses addresses) public {
        /// -------------- EMISSION CONFIGURATION --------------

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        address mrd = addresses.getAddress("MRD_PROXY");

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                _pushCrossChainAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        config.mToken,
                        config.owner,
                        config.emissionToken,
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    "Temporal governor accepts admin on Unitroller"
                );
            }
        }
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

    /// @notice assert that all the configurations are correctly set
    /// @dev this function is called after the proposal is executed to
    /// validate that all state transitions worked correctly
    function validate(Addresses addresses, address) public {
        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        MultiRewardDistributor distributor = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];
                MultiRewardDistributorCommon.MarketConfig
                    memory marketConfig = distributor.getConfigForMarket(
                        MToken(addresses.getAddress(config.mToken)),
                        config.emissionToken
                    );

                assertEq(marketConfig.owner, addresses.getAddress(config.owner));
                assertEq(marketConfig.emissionToken, config.emissionToken);
                assertEq(marketConfig.endTime, config.endTime);
                assertEq(
                    marketConfig.supplyEmissionsPerSec,
                    config.supplyEmissionPerSec
                );
                assertEq(
                    marketConfig.borrowEmissionsPerSec,
                    config.borrowEmissionsPerSec
                );
                assertEq(marketConfig.supplyGlobalIndex, 1e36);
                assertEq(marketConfig.borrowGlobalIndex, 1e36);
            }
        }
    }
}

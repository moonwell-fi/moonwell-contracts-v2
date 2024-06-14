//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

/// This MIP sets the reward speeds for different markets in the MultiRewardDistributor
/// contract. It is intended to be used as a template for future MIPs that need to set reward speeds.
/// The first step is to open `mainnetRewardStreams.json` and add the reward streams for the
/// different mTokens. Then generate calldata by adding MIP01 to the TestProposals file.
contract mipb01 is Proposal, CrossChainProposal, Configs {
    string public constant override name = "MIP01";

    /// @notice proposal's actions all happen on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
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

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that all the configurations are correctly set
    /// @dev this function is called after the proposal is executed to
    /// validate that all state transitions worked correctly
    function validate(Addresses addresses, address) public override {
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

                assertEq(
                    marketConfig.owner,
                    addresses.getAddress(config.owner)
                );
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

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
import {PrimaryFork} from "@utils/Enums.sol";

/// This MIP sets the reward speeds for different markets in the MultiRewardDistributor
contract mipb07 is Proposal, CrossChainProposal, Configs {
    string public constant override name = "MIPB07";

    function primaryForkId() public pure override returns (PrimaryFork) {
        return PrimaryFork.Base;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        string memory descriptionPath = vm.envOr(
            "LISTING_PATH",
            string(
                "./src/proposals/mips/examples/mip-market-listing/MarketListingDescription.md"
            )
        );
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);

        delete cTokenConfigurations[block.chainid]; /// wipe existing mToken Configs.sol
        delete emissions[block.chainid]; /// wipe existing reward loaded in Configs.sol

        {
            string memory mtokensPath = vm.envOr(
                "EMISSION_PATH",
                string(
                    "./src/proposals/mips/examples/mip-market-listing/RewardStreams.json"
                )
            );
            /// EMISSION_PATH="./src/proposals/mips/examples/mip-market-listing/RewardStreams.json"
            string memory fileContents = vm.readFile(mtokensPath);
            bytes memory rawJson = vm.parseJson(fileContents);
            EmissionConfig[] memory decodedEmissions = abi.decode(
                rawJson,
                (EmissionConfig[])
            );

            for (uint256 i = 0; i < decodedEmissions.length; i++) {
                emissions[block.chainid].push(decodedEmissions[i]);
            }
        }

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
                        addresses.getAddress(config.mToken),
                        addresses.getAddress(config.owner),
                        config.emissionToken,
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    config.mToken
                );
            }
        }
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that all the configurations are correctly set
    /// @dev this function is called after the proposal is executed to
    /// validate that all state transitions worked correctly
    function validate(Addresses addresses, address) public view override {
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

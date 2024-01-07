//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributorCommon.sol";

/// @notice This lists all new markets provided in `mainnetMTokens.json`
/// This is a template of a MIP proposal that can be used to add new mTokens
/// @dev be sure to include all necessary underlying and price feed addresses
/// in the Addresses.sol contract for the network the MTokens are being deployed on.
contract mipb13 is Proposal, CrossChainProposal, Configs {
    /// @notice the name of the proposal
    /// Read more here: https://forum.moonwell.fi/t/mip-b10-onboard-reth-as-collateral-on-base-deployment/672
    string public constant name = "MIP-B13 OP MRD Add";

    EmissionConfigV2[] public opEmissions;

    struct EmissionConfigV2 {
        uint256 borrowEmissionsPerSec;
        string emissionToken;
        uint256 endTime;
        string mToken;
        string owner;
        uint256 supplyEmissionPerSec;
    }

    constructor() {
        /// for example, should be set to
        /// LISTING_PATH="./src/proposals/mips/examples/mip-market-listing/MarketListingDescription.md"
        string
            memory descriptionPath = "./src/proposals/mips/mip-b13/MIP-B13.md";
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);

        {
            string
                memory mtokensPath = "./src/proposals/mips/mip-b13/RewardStreams.json";
            /// EMISSION_PATH="./src/proposals/mips/examples/mip-market-listing/RewardStreams.json"
            string memory fileContents = vm.readFile(mtokensPath);
            bytes memory rawJson = vm.parseJson(fileContents);
            EmissionConfigV2[] memory decodedEmissions = abi.decode(
                rawJson,
                (EmissionConfigV2[])
            );

            for (uint256 i = 0; i < decodedEmissions.length; i++) {
                require(
                    decodedEmissions[i].borrowEmissionsPerSec != 0,
                    "borrow speed must be gte 1"
                );
                opEmissions.push(decodedEmissions[i]);
            }
        }

        console.log("\n\n------------ LOAD STATS ------------");
        console.log("Loaded %d reward configs", opEmissions.length);
        console.log("\n\n");
    }

    /// @notice no contracts are deployed in this proposal
    function deploy(Addresses addresses, address deployer) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    function build(Addresses addresses) public override {
        /// -------------- EMISSION CONFIGURATION --------------

        EmissionConfigV2[]
            memory emissionConfig = getEmissionV2Configurations();
        MultiRewardDistributor mrd = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfigV2 memory config = emissionConfig[i];

                _pushCrossChainAction(
                    address(mrd),
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        addresses.getAddress(config.mToken),
                        addresses.getAddress(config.owner),
                        addresses.getAddress(config.emissionToken),
                        config.supplyEmissionPerSec,
                        config.borrowEmissionsPerSec,
                        config.endTime
                    ),
                    "Add emission config for MToken market in MultiRewardDistributor"
                );
            }
        }
    }

    function run(
        Addresses addresses,
        address
    ) public override(CrossChainProposal, MIPProposal) {
        printCalldata(addresses);
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        {
            EmissionConfigV2[]
                memory emissionConfig = getEmissionV2Configurations();
            MultiRewardDistributor distributor = MultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            unchecked {
                for (uint256 i = 0; i < emissionConfig.length; i++) {
                    EmissionConfigV2 memory config = emissionConfig[i];
                    MultiRewardDistributorCommon.MarketConfig
                        memory marketConfig = distributor.getConfigForMarket(
                            MToken(addresses.getAddress(config.mToken)),
                            addresses.getAddress(config.emissionToken)
                        );

                    assertEq(
                        marketConfig.owner,
                        addresses.getAddress(config.owner)
                    );
                    assertEq(
                        marketConfig.emissionToken,
                        addresses.getAddress(config.emissionToken)
                    );
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

    function getEmissionV2Configurations()
        public
        view
        returns (EmissionConfigV2[] memory)
    {
        EmissionConfigV2[] memory configs = new EmissionConfigV2[](
            opEmissions.length
        );

        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                configs[i] = EmissionConfigV2({
                    mToken: opEmissions[i].mToken,
                    owner: opEmissions[i].owner,
                    emissionToken: opEmissions[i].emissionToken,
                    supplyEmissionPerSec: opEmissions[i].supplyEmissionPerSec,
                    borrowEmissionsPerSec: opEmissions[i].borrowEmissionsPerSec,
                    endTime: opEmissions[i].endTime
                });
            }
        }

        return configs;
    }
}

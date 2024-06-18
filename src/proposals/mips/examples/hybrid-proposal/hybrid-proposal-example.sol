//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IMultichainGovernor} from "@protocol/governance/multichain/IMultichainGovernor.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

/// @notice DO NOT USE THIS IN PRODUCTION, this is a completely hypothetical example
/// adds stkwell as reward streams, completely hypothetical situation that makes no sense and would not work in production
/// DO_BUILD=true DO_VALIDATE=true DO_RUN=true DO_PRINT=true forge script src/proposals/mips/examples/hybrid-proposal/hybrid-proposal-example.sol:HybridProposalExample
contract HybridProposalExample is
    Configs,
    HybridProposal,
    MultichainGovernorDeploy
{
    string public constant override name = "Example Proposal";

    uint256 public constant NEW_VOTING_PERIOD = 6 days;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(
                "./src/proposals/mips/examples/hybrid-proposal/ProposalDescription.md"
            )
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public override returns (ProposalType) {
        return ProposalType.Base;
    }

    /// @notice create proposal actions
    function build(Addresses addresses) public override {
        vm.selectFork(ProposalType.Moonbeam);

        _pushHybridAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "updateVotingPeriod(uint256)",
                NEW_VOTING_PERIOD
            ),
            "Set voting period on Multichain Governor to 6 days",
            ProposalType.Moonbeam
        );

        vm.selectFork(primaryForkId());

        /// ensure no existing reward configs have already been loaded from Configs.sol
        require(
            cTokenConfigurations[block.chainid].length == 0,
            "no configs allowed"
        );
        require(
            emissions[block.chainid].length == 0,
            "no emission configs allowed"
        );

        {
            _setEmissionConfiguration(
                "./src/proposals/mips/examples/hybrid-proposal/mip-example.json"
            );
        }

        /// -------------- EMISSION CONFIGURATION --------------

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        address mrd = addresses.getAddress("MRD_PROXY");

        unchecked {
            for (uint256 i = 0; i < emissionConfig.length; i++) {
                EmissionConfig memory config = emissionConfig[i];

                _pushHybridAction(
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
                    string(
                        abi.encodePacked(
                            "Emission configuration set for ",
                            config.mToken
                        )
                    ),
                    ProposalType.Base
                );
            }
        }
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(ProposalType.Moonbeam);

        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(primaryForkId());

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(addresses, temporalGovernor);

        // switch back to the base fork so we can run the validations
        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(ProposalType.Moonbeam);

        IMultichainGovernor governor = IMultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        assertEq(
            governor.votingPeriod(),
            NEW_VOTING_PERIOD,
            "voting period not set correctly"
        );

        vm.selectFork(primaryForkId());

        /// get moonbeam chainid for the emissions as this is where the data was stored
        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            sendingChainIdToReceivingChainId[block.chainid]
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
                    addresses.getAddress(config.owner),
                    "emission owner incorrect"
                );
                assertEq(
                    marketConfig.emissionToken,
                    config.emissionToken,
                    "emission token incorrect"
                );
                assertEq(
                    marketConfig.endTime,
                    config.endTime,
                    "end time incorrect"
                );
                assertEq(
                    marketConfig.supplyEmissionsPerSec,
                    config.supplyEmissionPerSec,
                    "supply emission per second incorrect"
                );
                assertEq(
                    marketConfig.borrowEmissionsPerSec,
                    config.borrowEmissionsPerSec,
                    "borrow emission per second incorrect"
                );
                assertEq(
                    marketConfig.supplyGlobalIndex,
                    1e36,
                    "supply global index incorrect"
                );
                assertEq(
                    marketConfig.borrowGlobalIndex,
                    1e36,
                    "borrow global index incorrect"
                );
            }
        }

        vm.selectFork(primaryForkId());
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {MToken} from "@protocol/MToken.sol";
import "@forge-std/Test.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/MultiRewardDistributor/MultiRewardDistributorCommon.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

contract Proposal7 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP_UPDATE_MRD";

    struct EmissionConfig {
        uint256 borrowEmissionsPerSec;
        address emissionToken;
        uint256 endTime;
        string mToken;
        string owner;
        uint256 supplyEmissionPerSec;
    }

    /// mapping of all emission configs per chainid
    mapping(uint256 => EmissionConfig[]) public emissions;

    constructor() {
        bytes memory proposalDescription = bytes("Update MRD config");
        _setProposalDescription(proposalDescription);

        string memory fileContents = vm.readFile(
            "./src/proposals/mainnetRewardStreams.json"
        );

        vm.selectFork(baseForkId);
        bytes memory rawJson = vm.parseJson(fileContents);
        EmissionConfig[] memory decodedEmissions = abi.decode(
            rawJson,
            (EmissionConfig[])
        );

        for (uint256 i = 0; i < decodedEmissions.length; i++) {
            emissions[block.chainid].push(decodedEmissions[i]);
        }

        vm.selectFork(moonbeamForkId);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        vm.selectFork(baseForkId);

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );

        address mrd = addresses.getAddress("MRD_PROXY");

        for (uint256 i = 0; i < emissionConfig.length; i++) {
            _pushHybridAction(
                mrd,
                abi.encodeWithSignature(
                    "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                    emissionConfig[i].mToken,
                    emissionConfig[i].owner,
                    emissionConfig[i].emissionToken,
                    emissionConfig[i].supplyEmissionPerSec,
                    emissionConfig[i].borrowEmissionsPerSec,
                    emissionConfig[i].endTime
                ),
                "Update MRD config",
                false
            );
        }

        vm.selectFork(moonbeamForkId);
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        EmissionConfig[] memory emissionConfig = getEmissionConfigurations(
            block.chainid
        );
        MultiRewardDistributor distributor = MultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        vm.startPrank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        for (uint256 i = 0; i < emissionConfig.length; i++) {
            distributor._addEmissionConfig(
                MToken(addresses.getAddress(emissionConfig[i].mToken)),
                addresses.getAddress(emissionConfig[i].owner),
                emissionConfig[i].emissionToken,
                emissionConfig[i].supplyEmissionPerSec,
                emissionConfig[i].borrowEmissionsPerSec,
                emissionConfig[i].endTime
            );
        }

        vm.selectFork(moonbeamForkId);
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

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
        vm.selectFork(moonbeamForkId);
    }

    function getEmissionConfigurations(
        uint256 chainId
    ) public view returns (EmissionConfig[] memory) {
        EmissionConfig[] memory configs = new EmissionConfig[](
            emissions[chainId].length
        );

        unchecked {
            for (uint256 i = 0; i < configs.length; i++) {
                configs[i] = EmissionConfig({
                    mToken: emissions[chainId][i].mToken,
                    owner: emissions[chainId][i].owner,
                    emissionToken: emissions[chainId][i].emissionToken,
                    supplyEmissionPerSec: emissions[chainId][i]
                        .supplyEmissionPerSec,
                    borrowEmissionsPerSec: emissions[chainId][i]
                        .borrowEmissionsPerSec,
                    endTime: emissions[chainId][i].endTime
                });
            }
        }

        return configs;
    }
}

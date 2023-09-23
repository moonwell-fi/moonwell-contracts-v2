//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";

/// @notice This lists all new markets provided in `mainnetMTokens.json`
/// This is a template of a MIP proposal that can be used to add new mTokens
/// @dev be sure to include all necessary underlying and price feed addresses
/// in the Addresses.sol contract for the network the MTokens are being deployed on.
contract EnvReader is CrossChainProposal, ChainIds, Configs {
    /// @notice list of all mTokens that were added to the market with this proposal
    MToken[] public mTokens;

    /// @notice supply caps of all mTokens that were added to the market with this proposal
    uint256[] public supplyCaps;

    /// @notice borrow caps of all mTokens that were added to the market with this proposal
    uint256[] public borrowCaps;

    constructor() {
        /// for example, should be set to
        /// LISTING_PATH="./proposals/mips/examples/mip-market-listing/MarketListingDescription.md"
        string memory mipPath = vm.envString("MIP_PATH");
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(string(abi.encodePacked(mipPath, "/MIPDescription.md")))
        );

        _setProposalDescription(proposalDescription);

        delete cTokenConfigurations[block.chainid]; /// wipe existing mToken Configs.sol
        delete emissions[block.chainid]; /// wipe existing reward loaded in Configs.sol

        {
            /// MTOKENS_PATH="./proposals/mips/examples/mip-market-listing/MTokens.json"
            string memory fileContents = vm.readFile(
                string(abi.encodePacked(mipPath, "/MTokens.json"))
            );
            bytes memory rawJson = vm.parseJson(fileContents);

            CTokenConfiguration[] memory decodedJson = abi.decode(
                rawJson,
                (CTokenConfiguration[])
            );

            for (uint256 i = 0; i < decodedJson.length; i++) {
                require(
                    decodedJson[i].collateralFactor <= 0.95e18,
                    "collateral factor absurdly high, are you sure you want to proceed?"
                );

                /// possible to set supply caps and not borrow caps,
                /// but not set borrow caps and not set supply caps
                if (decodedJson[i].supplyCap != 0) {
                    require(
                        decodedJson[i].supplyCap > decodedJson[i].borrowCap,
                        "borrow cap gte supply cap, are you sure you want to proceed?"
                    );
                } else if (decodedJson[i].borrowCap != 0) {
                    revert("borrow cap must be set with a supply cap");
                }

                cTokenConfigurations[block.chainid].push(decodedJson[i]);
            }
        }

        {
            string memory fileContents = vm.envString(
                vm.readFile(
                    string(abi.encodePacked(mipPath, "/RewardStreams.json"))
                )
            );
            bytes memory rawJson = vm.parseJson(fileContents);
            EmissionConfig[] memory decodedEmissions = abi.decode(
                rawJson,
                (EmissionConfig[])
            );

            for (uint256 i = 0; i < decodedEmissions.length; i++) {
                emissions[block.chainid].push(decodedEmissions[i]);
            }
        }

        console.log("\n\n------------ LOAD STATS ------------");
        console.log(
            "Loaded %d MToken configs",
            cTokenConfigurations[block.chainid].length
        );
        console.log(
            "Loaded %d reward configs",
            emissions[block.chainid].length
        );
        console.log("\n\n");
    }
}

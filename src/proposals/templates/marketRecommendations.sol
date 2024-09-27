//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";

import "@protocol/utils/ChainIds.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract MarketRecommendationsTemplate is HybridProposal, Networks {
    using stdJson for string;
    using ChainIds for uint256;
    using stdStorage for StdStorage;

    struct MarketUpdate {
        int256 collateralFactor;
        string irm;
        string market;
        int256 reserveFactor;
    }

    mapping(uint256 chainId => MarketUpdate[]) public marketUpdates;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function name() external pure override returns (string memory) {
        return "MIP Market Recommendations Update";
    }

    function name() external pure override returns (string memory) {
        return "MIP Rewards Distribution";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function initProposal(Addresses addresses) public override {
        string memory encodedJson = vm.readFile(vm.envString("JSON_PATH"));

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;

            _saveChainMarketUpdate(addresses, chainId, encodedJson);
        }
    }

    function _saveChainMarketUpdate(
        Addresses addresses,
        uint256 chainId,
        bytes memory data
    ) internal {
        string memory chain = string.concat(".", vm.toString(chainId));

        MarketUpdate[] memory updates = abi.decode(data, (MarketUpdate[]));

        for (uint256 i = 0; i < updates.length; i++) {
            MarketUpdate memory update = updates[i];

            console.log("Updating market %s on chain %s", update.market, chain);

            console.log(
                "Reserve factor: %s, collateral factor: %s, IRM: %s",
                vm.toString(update.reserveFactor),
                vm.toString(update.collateralFactor),
                update.irm
            );

            marketUpdates[chainId].push(update);
        }
    }

    function _buildChainActions(Addresses addresses, uint256 chainId) {
        vm.selectFork(chainId.toForkId());
        MarketUpdate[] memory updates = marketUpdates[chainId];

        for (uint256 i = 0; i < updates.length; i++) {
            MarketUpdate memory rec = updates[i];
            if (rec.collateralFactor != -1) {
                _pushAction(
                    addresses.getAddress(rec.market),
                    abi.encodeWithSignature(
                        "_setCollateralFactor(uint256)",
                        rec.collateralFactor
                    ),
                    string(
                        abi.encodePacked(
                            "Set collateral factor for ",
                            rec.market
                        )
                    )
                );
            }

            if (rec.reserveFactor != -1) {
                _pushAction(
                    addresses.getAddress(rec.market),
                    abi.encodeWithSignature(
                        "_setReserveFactor(uint256)",
                        rec.reserveFactor
                    ),
                    string(
                        abi.encodePacked("Set reserve factor for ", rec.market)
                    )
                );
            }

            if (keccak256(abi.encodePacked(rec.irm)) != keccak256("")) {
                _pushAction(
                    addresses.getAddress(rec.market),
                    abi.encodeWithSignature(
                        "_setInterestRateModel(string)",
                        rec.irm
                    ),
                    string(abi.encodePacked("Set IRM for ", rec.market))
                );
            }
        }
    }

    function validate(Addresses addresses, address) public view override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;

            //_validateChain(addresses, chainId);
        }
    }
}

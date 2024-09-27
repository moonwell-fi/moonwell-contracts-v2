//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";

import {Networks} from "@proposals/utils/Networks.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract MarketRecommendationsTemplate is HybridProposal, Networks {
    using stdJson for string;

    struct MarketUpdate {
        uint256 collateralFactor;
        string irm;
        string market;
        uint256 reserveFactor;
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

    function initProposal(Addresses addresses) public override {
        string memory encodedJson = vm.readFile(vm.envString("JSON_PATH"));

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            string memory data = encodedJson.get(networks[i].name);

            _saveChainMarketUpdate(addresses, chainId, data);
        }
    }

    function _saveChainMarketUpdate(
        Addresses addresses,
        uint256 chainId,
        string memory data
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
        }
    }
}

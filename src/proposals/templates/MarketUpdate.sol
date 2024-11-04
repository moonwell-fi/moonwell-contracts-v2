//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "@protocol/utils/ChainIds.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

contract MarketUpdateTemplate is HybridProposal, Networks, ParameterValidation {
    using SafeCast for *;
    using stdJson for string;
    using ChainIds for uint256;
    using stdStorage for StdStorage;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct MarketUpdate {
        int256 collateralFactor;
        string jrm;
        string market;
        int256 reserveFactor;
    }

    struct JRM {
        uint256 baseRatePerTimestamp;
        uint256 jumpMultiplierPerTimestamp;
        uint256 kink;
        uint256 multiplierPerTimestamp;
        string name;
    }

    mapping(uint256 chainId => MarketUpdate[]) public marketUpdates;
    mapping(uint256 chainId => mapping(string name => JRM)) public irModels;
    mapping(uint256 chainId => EnumerableSet.AddressSet markets)
        private _markets;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function name() external pure override returns (string memory) {
        return "MIP Market Update";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function initProposal(Addresses addresses) public override {
        string memory encodedJson = vm.readFile(vm.envString("JSON_PATH"));

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;

            _saveChainMarketUpdate(addresses, chainId, encodedJson);
            _saveIRModels(addresses, chainId, encodedJson);
        }
    }

    function build(Addresses addresses) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _buildChainActions(addresses, chainId);
        }
    }

    function _saveChainMarketUpdate(
        Addresses addresses,
        uint256 chainId,
        string memory data
    ) internal {
        string memory chain = string.concat(
            ".",
            vm.toString(chainId),
            ".markets"
        );

        if (!vm.keyExistsJson(data, chain)) {
            return;
        }

        vm.selectFork(chainId.toForkId());

        bytes memory parsedJson = vm.parseJson(data, chain);

        MarketUpdate[] memory updates = abi.decode(
            parsedJson,
            (MarketUpdate[])
        );

        for (uint256 i = 0; i < updates.length; i++) {
            MarketUpdate memory rec = updates[i];

            address market = addresses.getAddress(rec.market);
            require(market != address(0), "Market address is not set");

            require(!_markets[chainId].contains(market), "Market already set");

            marketUpdates[chainId].push(rec);
        }
    }

    function _saveIRModels(
        Addresses addresses,
        uint256 chainId,
        string memory data
    ) internal {
        string memory chain = string.concat(
            ".",
            vm.toString(chainId),
            ".irModels"
        );

        if (!vm.keyExistsJson(data, chain)) {
            return;
        }

        vm.selectFork(chainId.toForkId());

        bytes memory parsedJson = vm.parseJson(data, chain);

        JRM[] memory models = abi.decode(parsedJson, (JRM[]));

        for (uint256 i = 0; i < models.length; i++) {
            JRM memory model = models[i];

            require(
                addresses.getAddress(model.name) != address(0),
                "JRM address is not set"
            );

            irModels[chainId][model.name] = model;
        }
    }

    function _buildChainActions(Addresses addresses, uint256 chainId) public {
        vm.selectFork(chainId.toForkId());

        MarketUpdate[] memory updates = marketUpdates[chainId];
        address unitroller = addresses.getAddress("UNITROLLER");

        for (uint256 i = 0; i < updates.length; i++) {
            MarketUpdate memory rec = updates[i];
            if (rec.reserveFactor != -1) {
                _pushAction(
                    addresses.getAddress(rec.market),
                    abi.encodeWithSignature(
                        "_setReserveFactor(uint256)",
                        rec.reserveFactor.toUint256()
                    ),
                    string(
                        abi.encodePacked(
                            "Set reserve factor to ",
                            vm.toString(rec.reserveFactor),
                            " for ",
                            rec.market
                        )
                    )
                );
            }

            if (rec.collateralFactor != -1) {
                _pushAction(
                    unitroller,
                    abi.encodeWithSignature(
                        "_setCollateralFactor(address,uint256)",
                        addresses.getAddress(rec.market),
                        rec.collateralFactor.toUint256()
                    ),
                    string(
                        abi.encodePacked(
                            "Set collateral factor to ",
                            vm.toString(rec.collateralFactor),
                            " for ",
                            rec.market
                        )
                    )
                );
            }

            if (keccak256(abi.encodePacked(rec.jrm)) != keccak256("")) {
                _pushAction(
                    addresses.getAddress(rec.market),
                    abi.encodeWithSignature(
                        "_setInterestRateModel(address)",
                        addresses.getAddress(rec.jrm)
                    ),
                    string(
                        abi.encodePacked(
                            "Set JRM for ",
                            vm.toString(addresses.getAddress(rec.jrm)),
                            " for ",
                            rec.market
                        )
                    )
                );
            }
        }
    }

    function validate(Addresses addresses, address) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _validateChain(addresses, chainId);
        }
    }

    function _validateChain(Addresses addresses, uint256 chainId) private {
        vm.selectFork(chainId.toForkId());
        MarketUpdate[] memory updates = marketUpdates[chainId];

        for (uint256 i = 0; i < updates.length; i++) {
            MarketUpdate memory rec = updates[i];

            if (rec.collateralFactor != -1) {
                _validateCF(
                    addresses,
                    addresses.getAddress(rec.market),
                    rec.collateralFactor.toUint256()
                );
            }

            if (rec.reserveFactor != -1) {
                _validateRF(
                    addresses.getAddress(rec.market),
                    rec.reserveFactor.toUint256()
                );
            }

            if (keccak256(abi.encodePacked(rec.jrm)) != keccak256("")) {
                JRM memory params = irModels[chainId][rec.jrm];
                _validateJRM(
                    addresses.getAddress(rec.jrm),
                    addresses.getAddress(rec.market),
                    IRParams({
                        baseRatePerTimestamp: params.baseRatePerTimestamp,
                        kink: params.kink,
                        multiplierPerTimestamp: params.multiplierPerTimestamp,
                        jumpMultiplierPerTimestamp: params
                            .jumpMultiplierPerTimestamp
                    })
                );
            }
        }
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import "@protocol/utils/ChainIds.sol";
import {Networks} from "@proposals/utils/Networks.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";

contract MarketUpdateTemplate is HybridProposal, Networks, ParameterValidation {
    using SafeCast for *;
    using stdJson for string;
    using ChainIds for uint256;
    using stdStorage for StdStorage;
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    struct MarketUpdate {
        int256 collateralFactor;
        string jrm;
        string market;
        int256 reserveFactor;
    }

    struct JRM {
        uint256 baseRatePerYear;
        uint256 jumpMultiplierPerYear;
        uint256 kink;
        uint256 multiplierPerYear;
        string name;
    }

    mapping(uint256 chainId => MarketUpdate[]) public marketUpdates;
    mapping(uint256 chainId => mapping(string name => JRM)) public irModels;
    mapping(uint256 chainId => string[] names) private _irmNames;
    mapping(uint256 chainId => EnumerableSet.AddressSet markets)
        private _markets;
    mapping(uint256 chainId => EnumerableSet.Bytes32Set models)
        private _irModels;

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

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) run(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function initProposal(Addresses addresses) public override {
        string memory encodedJson = vm.readFile(vm.envString("JSON_PATH"));

        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;

            _saveChainMarketUpdate(addresses, chainId, encodedJson);
            _saveIRModels(chainId, encodedJson);
        }
    }

    function deploy(Addresses addresses, address deployer) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _deployIRModels(addresses, deployer, chainId);
        }
    }

    function build(Addresses addresses) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _buildChainActions(addresses, chainId);
        }
    }

    function validate(Addresses addresses, address) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            _validateChain(addresses, chainId);
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

            require(_markets[chainId].add(market), "Duplication in Markets");

            marketUpdates[chainId].push(rec);
        }
    }

    function _saveIRModels(uint256 chainId, string memory data) internal {
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
                _irModels[chainId].add(bytes32(abi.encodePacked(model.name))),
                "Duplicate IR model"
            );

            irModels[chainId][model.name] = model;
            _irmNames[chainId].push(model.name);
        }
    }

    function _deployIRModels(
        Addresses addresses,
        address deployer,
        uint256 chainId
    ) internal {
        vm.selectFork(chainId.toForkId());

        for (uint256 i = 0; i < _irmNames[chainId].length; i++) {
            JRM memory model = irModels[chainId][_irmNames[chainId][i]];

            if (!addresses.isAddressSet(model.name)) {
                vm.startBroadcast(deployer);
                address irModel = address(
                    new JumpRateModel(
                        model.baseRatePerYear,
                        model.multiplierPerYear,
                        model.jumpMultiplierPerYear,
                        model.kink
                    )
                );
                vm.stopBroadcast();

                addresses.addAddress(model.name, address(irModel));
            }
        }
    }

    function _buildChainActions(Addresses addresses, uint256 chainId) internal {
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

    function _validateChain(Addresses addresses, uint256 chainId) internal {
        MarketUpdate[] memory updates = marketUpdates[chainId];
        if (updates.length == 0) {
            return;
        }

        vm.selectFork(chainId.toForkId());

        if (updates.length == 0) {
            return;
        }

        vm.selectFork(chainId.toForkId());

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
                        baseRatePerTimestamp: params.baseRatePerYear,
                        kink: params.kink,
                        multiplierPerTimestamp: params.multiplierPerYear,
                        jumpMultiplierPerTimestamp: params.jumpMultiplierPerYear
                    })
                );
            }
        }
    }
}

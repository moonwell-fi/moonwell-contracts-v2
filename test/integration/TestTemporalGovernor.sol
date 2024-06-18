//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Unitroller} from "@protocol/Unitroller.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

contract TemporalGovernorProposalIntegrationTest is Configs, HybridProposal {
    string public constant override name = "TEST_TEMPORAL_GOVERNOR";

    uint256 public constant collateralFactor = 0.6e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            "Set collateral factor to 0.6e18 for MOONWELL_WETH on Moonbeam."
        );
        _setProposalDescription(proposalDescription);
    }

    function run() public override {
        uint256[] memory _forkIds = new uint256[](2);

        _forkIds[0] = vm.createFork(
            vm.envOr("MOONBEAM_RPC_URL", string("moonbeam"))
        );
        _forkIds[1] = vm.createFork(vm.envOr("BASE_RPC_URL", string("base")));

        setForkIds(_forkIds);

        super.run();
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress(
                "UNITROLLER",
                sendingChainIdToReceivingChainId[block.chainid]
            ),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress(
                    "MOONWELL_WETH",
                    sendingChainIdToReceivingChainId[block.chainid]
                ),
                collateralFactor
            ),
            "Set collateral factor",
            false
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(forkIds(1));
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(addresses, temporalGovernor);

        vm.selectFork(forkIds(0));
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(forkIds(1));

        Comptroller unitroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        (, uint256 collateralFactorMantissa) = unitroller.markets(
            addresses.getAddress("MOONWELL_WETH")
        );
        assertEq(collateralFactorMantissa, collateralFactor);

        vm.selectFork(forkIds(0));
    }
}

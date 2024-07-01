//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Unitroller} from "@protocol/Unitroller.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";

contract TemporalGovernorProposalIntegrationTest is Configs, HybridProposal {
    string public constant override name = "TEST_TEMPORAL_GOVERNOR";

    uint256 public constant collateralFactor = 0.6e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            "Set collateral factor to 0.6e18 for MOONWELL_WETH on Moonbeam."
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress("UNITROLLER", block.chainid.toBaseChainId()),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress(
                    "MOONWELL_WETH",
                    block.chainid.toBaseChainId()
                ),
                collateralFactor
            ),
            "Set collateral factor",
            false
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(addresses, temporalGovernor);

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        Comptroller unitroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        (, uint256 collateralFactorMantissa) = unitroller.markets(
            addresses.getAddress("MOONWELL_WETH")
        );
        assertEq(collateralFactorMantissa, collateralFactor);

        vm.selectFork(primaryForkId());
    }
}

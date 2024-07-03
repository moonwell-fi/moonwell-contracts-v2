//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Unitroller} from "@protocol/Unitroller.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ForkID} from "@utils/Enums.sol";

contract TemporalGovernorProposalIntegrationTest is Configs, HybridProposal {
    string public constant override name = "TEST_TEMPORAL_GOVERNOR";

    uint256 public constant collateralFactor = 0.6e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            "Set collateral factor to 0.6e18 for MOONWELL_WETH on Moonbeam."
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Moonbeam;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        _pushAction(
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
            ForkID.Base
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(uint256(ForkID.Base));
        _runExtChain(addresses, baseActions);

        require(baseActions.length == 1, "invalid base proposal length");
        require(
            moonbeamActions.length == 1,
            "invalid moonbeam proposal length"
        );

        vm.selectFork(uint256(primaryForkId()));
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(uint256(ForkID.Base));

        Comptroller unitroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );

        (, uint256 collateralFactorMantissa) = unitroller.markets(
            addresses.getAddress("MOONWELL_WETH")
        );
        assertEq(collateralFactorMantissa, collateralFactor);

        vm.selectFork(uint256(primaryForkId()));
    }
}

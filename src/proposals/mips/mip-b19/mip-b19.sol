//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b19/mip-b19.sol:mipb19
contract mipb19 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B19";

    uint128 public constant NEW_REWARD_SPEED = 2.475835385901440000 * 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-B19/MIP-B19.md")
        );

        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions all happen on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushCrossChainAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                NEW_REWARD_SPEED,
                addresses.getAddress("xWELL_PROXY")
            ),
            "Set new reward speed to 2.475835385901440000 WELL per second"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        IStakedWellUplift stkWell = IStakedWellUplift(
            addresses.getAddress("STK_GOVTOKEN")
        );
        (uint128 emissionsPerSecond, , ) = stkWell.assets(
            addresses.getAddress("xWELL_PROXY")
        );

        assertEq(emissionsPerSecond, NEW_REWARD_SPEED, "emissionsPerSecond");
    }
}

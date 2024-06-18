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
/// src/proposals/mips/mip-b20/mip-b20.sol:mipb20
contract mipb20 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B20";

    uint128 public constant NEW_REWARD_SPEED = 2.475835385901440000 * 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b20/MIP-B20.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ProposalType) {
        return ProposalType.Base;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushCrossChainAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                NEW_REWARD_SPEED,
                addresses.getAddress("STK_GOVTOKEN")
            ),
            "Set new reward speed to 2.475835385901440000 WELL per second"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        IStakedWellUplift stkWell = IStakedWellUplift(
            addresses.getAddress("STK_GOVTOKEN")
        );
        (uint128 emissionsPerSecond, , ) = stkWell.assets(
            addresses.getAddress("STK_GOVTOKEN")
        );

        assertEq(emissionsPerSecond, NEW_REWARD_SPEED, "emissionsPerSecond");
    }
}

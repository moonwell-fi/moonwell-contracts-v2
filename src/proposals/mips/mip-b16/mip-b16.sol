//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {ITokenSaleDistributorProxy} from "@protocol/tokensale/ITokenSaleDistributorProxy.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b16/mip-b16.sol:mipb16
contract mipb16 is
    HybridProposal,
    MultichainGovernorDeploy,
    ParameterValidation
{
    string public constant name = "MIP-B16";

    /// TODO this is TBD and based on the current state of the system
    uint256 public constant REWARD_SPEED = 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b16/MIP-B16.md")
        );

        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions happen only on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Base actions

        _pushHybridAction(
            addresses.getAddress("stkWELL_PROXY"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                REWARD_SPEED,
                addresses.getAddress("stkWELL_PROXY")
            ),
            "Set reward speed for the Safety Module on Base",
            false
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 1,
            "MIP-M26: should have no base actions"
        );
        require(
            moonbeamActions.length == 0,
            "MIP-M26: should have no base actions"
        );

        /// only run actions on Base
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(baseForkId);
        _runBase(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    /// TODO fill out validations on Base
    function validate(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        address stkWellProxy = addresses.getAddress("stkWELL_PROXY");
        (
            uint128 emissionsPerSecond,
            uint128 lastUpdateTimestamp,

        ) = IStakedWell(stkWellProxy).assets(stkWellProxy);

        assertEq(
            emissionsPerSecond,
            REWARD_SPEED,
            "MIP-M26: emissionsPerSecond incorrect"
        );

        assertGt(
            lastUpdateTimestamp,
            0,
            "MIP-M26: lastUpdateTimestamp not set"
        );
    }
}

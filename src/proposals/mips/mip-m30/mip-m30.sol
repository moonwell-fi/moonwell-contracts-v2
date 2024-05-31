//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

import {ITimelock as Timelock} from "@protocol/interfaces/ITimelock.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {MToken} from "@protocol/MToken.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";

contract mipm30 is Configs, HybridProposal, GovernanceProposal {
    string public constant override name = "MIP-M30";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m30/MIP-M30.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        /// set pending admin of mWBTCwh to the Multichain Governor
        _pushGovernanceAction(
            addresses.getAddress("mWBTCwh"),
            "Set the pending admin of the new wBTC market to the Multichain Governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );
    }

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
        setDebug(true);

        _simulateGovernanceActions(
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            address(this)
        );
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");

        assertEq(
            Timelock(addresses.getAddress("mWBTCwh")).pendingAdmin(),
            governor,
            "mWBTCwh pending admin incorrect"
        );
    }
}

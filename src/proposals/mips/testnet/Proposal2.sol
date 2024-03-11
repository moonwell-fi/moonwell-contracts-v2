//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {Ownable} from "@openzeppelin-contracts/contracts/access/Ownable.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import "@forge-std/Test.sol";

import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeTrustedSender} from "@protocol/Governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

//- Move temporal governor ownership back to artemis
//- Move bridge adapter ownership back to artemis
//- Move xwell ownership back to artemis
//- Move distributor ownership back to artemis
//- Remove old governor as a trusted sender on temporal governor
contract Proposal2 is HybridProposal, MultichainGovernorDeploy {
    string public constant name = "MIP-M18E";

    constructor() {
        _setProposalDescription(
            bytes("Transfer lending system Moonbase ownership")
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");

        address timelock = addresses.getAddress(
            "MOONBEAM_TIMELOCK",
            sendingChainIdToReceivingChainId[block.chainid]
        );

        {
            ITemporalGovernor.TrustedSender[]
                memory temporalGovernanceTrustedSenders = new ITemporalGovernor.TrustedSender[](
                    1
                );

            temporalGovernanceTrustedSenders[0].addr = timelock;
            temporalGovernanceTrustedSenders[0]
                .chainId = moonBeamWormholeChainId;

            _pushHybridAction(
                temporalGovernor,
                abi.encodeWithSignature(
                    "setTrustedSenders((uint16,address)[])",
                    temporalGovernanceTrustedSenders
                ),
                "Add Timelock as a trusted sender to the Temporal Governor",
                false
            );
        }

        {
            ITemporalGovernor.TrustedSender[]
                memory temporalGovernanceTrustedSenders = new ITemporalGovernor.TrustedSender[](
                    1
                );

            // old governor
            temporalGovernanceTrustedSenders[0]
                .addr = 0x716ff5a3Acbcd6cA05e921a524b80B5B68FAca05;
            temporalGovernanceTrustedSenders[0]
                .chainId = moonBeamWormholeChainId;

            _pushHybridAction(
                temporalGovernor,
                abi.encodeWithSignature(
                    "unSetTrustedSenders((uint16,address)[])",
                    temporalGovernanceTrustedSenders
                ),
                "Add Timelock as a trusted sender to the Temporal Governor",
                false
            );
        }

        vm.selectFork(moonbeamForkId);

        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("transferOwnership(address)", timelock),
            "Set the pending owner of the Wormhole Bridge Adapter to Timelock",
            true
        );

        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature("transferOwnership(address)", timelock),
            "Set the pending owner of the xWELL Token to the Multichain Governor",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamArtemisGovernor(
            addresses.getAddress("WORMHOLE_CORE"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            addresses.getAddress("WELL"),
            address(1000000000)
        );

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _runBase(temporalGovernor);

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        TemporalGovernor temporalGovernor = TemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        // get all trusted senders
        bytes32[] memory trustedSenders = temporalGovernor.allTrustedSenders(
            chainIdToWormHoleId[block.chainid]
        );

        assertEq(trustedSenders.length, 1);

        vm.selectFork(moonbeamForkId);

        assertEq(
            trustedSenders[0],
            keccak256(
                abi.encodePacked(addresses.getAddress("MOONBEAM_TIMELOCK"))
            )
        );

        assertEq(
            Ownable(addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"))
                .owner(),
            addresses.getAddress("MOONBEAM_TIMELOCK")
        );
        assertEq(
            Ownable(addresses.getAddress("xWELL_PROXY")).owner(),
            addresses.getAddress("MOONBEAM_TIMELOCK")
        );
    }
}

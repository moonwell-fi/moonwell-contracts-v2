pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Script} from "@forge-std/Script.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import "@forge-std/Test.sol";

contract ValidateActiveProposals is Script, Test, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        uint256[] memory proposalIds = governor.liveProposals();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            (address[] memory targets, , bytes[] memory calldatas) = governor
                .getProposalData(proposalIds[i]);

            for (uint256 j = 1; j < targets.length; j++) {
                require(
                    targets[j].code.length > 0,
                    "Proposal target not a contract"
                );
            }

            address wormholeCore = block.chainid == moonBeamChainId
                ? addresses.getAddress("WORMHOLE_CORE_MOONBEAM")
                : addresses.getAddress("WORMHOLE_CORE_MOONBASE");

            uint256 lastIndex = targets.length - 1;
            if (targets[lastIndex] == wormholeCore) {
                console.log("Wormhole Core address mismatch");
                // decode calldatas
                (, bytes memory payload, ) = abi.decode(
                    calldatas[lastIndex],
                    (uint32, bytes, uint8)
                );
                console.log("after decode calldatas");

                // decode payload
                (
                    address temporalGovernorAddress,
                    address[] memory targets,
                    uint256[] memory values,
                    bytes[] memory payloads
                ) = abi.decode(
                        payload,
                        (address, address[], uint256[], bytes[])
                    );

                address expectedTemporalGov = block.chainid == moonBeamChainId
                    ? addresses.getAddress("TEMPORAL_GOVERNOR", baseChainId)
                    : addresses.getAddress(
                        "TEMPORAL_GOVERNOR",
                        baseSepoliaChainId
                    );
                require(
                    temporalGovernorAddress == expectedTemporalGov,
                    "Temporal Governor address mismatch"
                );
            }
        }
    }

    //    function executeOnBase() {
    //        bytes memory payload = abi.encode(
    //            temporalGovernorAddress,
    //            targets,
    //            values,
    //            payloads
    //        );
    //
    //        bytes32 governor = addressToBytes(
    //            addresses.getAddress(
    //                "MULTICHAIN_GOVERNOR_PROXY",
    //                sendingChainIdToReceivingChainId[block.chainid]
    //            )
    //        );
    //
    //        bytes memory vaa = generateVAA(
    //            uint32(block.timestamp),
    //            uint16(chainIdToWormHoleId[baseChainId]),
    //            governor,
    //            payload
    //        );
    //
    //        ITemporalGovernor temporalGovernor = ITemporalGovernor(
    //            temporalGovernorAddress
    //        );
    //
    //        temporalGovernor.queueProposal(vaa);
    //
    //        vm.warp(block.timestamp + temporalGovernor.proposalDelay());
    //
    //        temporalGovernor.executeProposal(vaa);
    //
    //    }
}

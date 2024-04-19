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
            uint256 proposalId = proposalIds[i];
            (address[] memory targets, , bytes[] memory calldatas) = governor
                .getProposalData(proposalId);

            for (uint256 j = 0; j < targets.length; j++) {
                require(
                    targets[j].code.length > 0,
                    "Proposal target not a contract"
                );

                // Simulate proposals execution
                address well = addresses.getAddress("WELL");

                // cast votes
                deal(well, address(this), governor.quorum());
                governor.castVote(proposalId, 0);

                (
                    ,
                    ,
                    ,
                    ,
                    uint256 crossChainVoteCollectionEndTimestamp,
                    ,
                    ,
                    ,

                ) = governor.proposalInformation(proposalId);

                vm.warp(crossChainVoteCollectionEndTimestamp + 1);

                governor.execute(proposalId);
            }

            // Check if there is any action on Base
            address wormholeCore = block.chainid == moonBeamChainId
                ? addresses.getAddress("WORMHOLE_CORE_MOONBEAM")
                : addresses.getAddress("WORMHOLE_CORE_MOONBASE");

            uint256 lastIndex = targets.length - 1;

            if (targets[lastIndex] == wormholeCore) {
                // decode calldatas
                (, bytes memory payload, ) = abi.decode(
                    slice(
                        calldatas[lastIndex],
                        4,
                        calldatas[lastIndex].length - 4
                    ),
                    (uint32, bytes, uint8)
                );

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

    // Utility function to slice bytes array
    function slice(
        bytes memory data,
        uint start,
        uint length
    ) internal pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }
}

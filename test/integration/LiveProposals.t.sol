pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {MIPProposal as Proposal} from "@proposals/MIPProposal.s.sol";

contract LiveProposalsIntegrationTest is Test, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice array of proposals added/changed in the current branch
    Proposal[] public proposals;

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(
            vm.envOr("MOONBEAM_RPC_URL", string("moonbase")),
            6737902
        );

    /// @notice fork ID for base
    uint256 public baseForkId =
        vm.createFork(vm.envOr("BASE_RPC_URL", string("baseSepolia")));

    function setUp() public {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        //git diff --name-only -- src/proposals/mips/
        string[] memory inputs = new string[](1);
        inputs[0] = "./branch-proposals.sh";

        string memory output = string(vm.ffi(inputs));

        // Convert output to array of lines
        string[] memory lines = splitString(output, "\n");

        proposals = new Proposal[](lines.length);

        for (uint i = 0; i < lines.length; i++) {
            address proposal = deployCode(lines[i]);
            proposals[i] = Proposal(proposal);
            vm.makePersistent(proposal);
        }
    }

    function testBranchProposals() public {
        for (uint i = 0; i < proposals.length; i++) {
            proposals[i].run(addresses, address(this));
        }
    }

    function testActiveProposals() public {
        vm.selectFork(moonbeamForkId);
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

                {
                    // Simulate proposals execution
                    (
                        ,
                        uint256 voteSnapshotTimestamp,
                        uint256 votingStartTime,
                        ,
                        uint256 crossChainVoteCollectionEndTimestamp,
                        ,
                        ,
                        ,

                    ) = governor.proposalInformation(proposalId);

                    address well = addresses.getAddress("xWELL_PROXY");
                    vm.warp(voteSnapshotTimestamp - 1);
                    deal(well, address(this), governor.quorum());
                    xWELL(well).delegate(address(this));

                    vm.warp(votingStartTime);
                    governor.castVote(proposalId, 0);

                    vm.warp(crossChainVoteCollectionEndTimestamp + 1);

                    governor.execute(proposalId);
                }
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

                vm.selectFork(baseForkId);
                address expectedTemporalGov = block.chainid == baseChainId
                    ? addresses.getAddress("TEMPORAL_GOVERNOR", baseChainId)
                    : addresses.getAddress(
                        "TEMPORAL_GOVERNOR",
                        baseSepoliaChainId
                    );

                {
                    // decode payload
                    (
                        address temporalGovernorAddress,
                        address[] memory baseTargets,
                        ,

                    ) = abi.decode(
                            payload,
                            (address, address[], uint256[], bytes[])
                        );

                    require(
                        temporalGovernorAddress == expectedTemporalGov,
                        "Temporal Governor address mismatch"
                    );

                    for (uint256 j = 0; j < baseTargets.length; j++) {
                        require(
                            baseTargets[j].code.length > 0,
                            "Proposal target not a contract"
                        );
                    }
                }

                bytes memory vaa = generateVAA(
                    uint32(block.timestamp),
                    uint16(chainIdToWormHoleId[block.chainid]),
                    addressToBytes(address(governor)),
                    payload
                );

                TemporalGovernor temporalGovernor = TemporalGovernor(
                    expectedTemporalGov
                );

                // Deploy the modified Wormhole Core implementation contract which
                // bypass the guardians signature check
                Implementation core = new Implementation();
                address wormhole = block.chainid == baseChainId
                    ? addresses.getAddress("WORMHOLE_CORE_BASE", baseChainId)
                    : addresses.getAddress(
                        "WORMHOLE_CORE_SEPOLIA_BASE",
                        baseSepoliaChainId
                    );

                /// Set the wormhole core address to have the
                /// runtime bytecode of the mock core
                vm.etch(wormhole, address(core).code);

                temporalGovernor.queueProposal(vaa);

                vm.warp(block.timestamp + temporalGovernor.proposalDelay());

                temporalGovernor.executeProposal(vaa);
            }
        }
    }

    /// @dev utility function to generate a Wormhole VAA payload excluding the guardians signature
    function generateVAA(
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        bytes memory payload
    ) private pure returns (bytes memory encodedVM) {
        uint64 sequence = 200;
        uint8 version = 1;
        uint32 nonce = 0;
        uint8 consistencyLevel = 200;

        encodedVM = abi.encodePacked(
            version,
            timestamp,
            nonce,
            emitterChainId,
            emitterAddress,
            sequence,
            consistencyLevel,
            payload
        );
    }

    /// @dev utility function to convert an address to bytes32
    function addressToBytes(address addr) private pure returns (bytes32) {
        return bytes32(bytes20(addr)) >> 96;
    }

    // @dev Utility function to slice bytes array
    function slice(
        bytes memory data,
        uint start,
        uint length
    ) private pure returns (bytes memory) {
        bytes memory part = new bytes(length);
        for (uint i = 0; i < length; i++) {
            part[i] = data[i + start];
        }
        return part;
    }

    // @dev Utility function to split string by delimiter
    function splitString(
        string memory _base,
        string memory _value
    ) private pure returns (string[] memory splitArr) {
        bytes memory base = bytes(_base);
        bytes memory value = bytes(_value);
        uint count = 1;
        for (uint i = 0; i < base.length; i++) {
            if (base[i] == value[0]) {
                count++;
            }
        }

        splitArr = new string[](count);
        uint index = 0;
        uint lastIndex = 0;
        for (uint i = 0; i < base.length; i++) {
            if (base[i] == value[0]) {
                bytes memory word = new bytes(i - lastIndex);
                for (uint j = lastIndex; j < i; j++) {
                    word[j - lastIndex] = base[j];
                }
                splitArr[index] = string(word);
                index++;
                lastIndex = i + 1;
            }
        }
        if (lastIndex <= base.length) {
            bytes memory word = new bytes(base.length - lastIndex);
            for (uint j = lastIndex; j < base.length; j++) {
                word[j - lastIndex] = base[j];
            }
            splitArr[index] = string(word);
        }
    }
}

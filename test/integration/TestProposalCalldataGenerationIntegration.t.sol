// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import "@protocol/utils/ChainIds.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from "@protocol/interfaces/IArtemisGovernor.sol";
import {MultichainGovernor, IMultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract TestProposalCalldataGeneration is ProposalMap, Test {
    using ChainIds for uint256;

    Addresses public addresses;

    MultichainGovernor public governor;
    MoonwellArtemisGovernor public artemisGovernor;

    mapping(uint256 proposalId => bytes32 hash) public proposalHashes;
    mapping(uint256 proposalId => bytes32 hash) public artemisProposalHashes;

    function setUp() public {
        MOONBEAM_FORK_ID.createForksAndSelect();
        addresses = new Addresses();

        vm.makePersistent(address(this));
        vm.makePersistent(address(addresses));

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        artemisGovernor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );
    }

    function _isExcludedMultichain(uint256 id) internal pure returns (bool) {
        // exclude proposals that are not onchain yet or proposals with dynamic calldata:
        // 127 (mip-x34), 121 (mip-x32), 137 (mip-b55: bridgeCost is dynamic),
        // 134 (mip-x38), 141 (mip-x43), 143 (mip-b57): inherit ChainlinkOracleConfigs
        // which grows when new markets are added
        // 147 (mip-b58): bridgeCost changed after x48 (FIND-002)
        // 148 (MarketUpdate), 150 (MarketAddV3), 151 (RewardsDistribution):
        // heavy templates that OOM on CI runners due to large config imports
        return
            id == 0 ||
            id == 121 ||
            id == 127 ||
            id == 134 ||
            id == 137 ||
            id == 141 ||
            id == 143 ||
            id == 147 ||
            id == 148 ||
            id == 150 ||
            id == 151;
    }

    function _verifyMultichainProposal(ProposalFields memory p) internal {
        setEnv(p.envPath);

        string memory proposalPath = p.path;

        console.log("Proposal path: ", proposalPath);
        console.log("Proposal env path: ", p.envPath);

        HybridProposal proposal = HybridProposal(deployCode(proposalPath));
        vm.label(
            address(proposal),
            string(
                abi.encodePacked(
                    "Proposal ",
                    proposal.name(),
                    " - ",
                    proposalPath
                )
            )
        );
        vm.makePersistent(address(proposal));

        vm.selectFork(proposal.primaryForkId());

        proposal.initProposal(addresses);
        proposal.build(addresses);

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = proposal.getTargetsPayloadsValues(addresses);
        bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

        cleanEnv(p.envPath);

        vm.selectFork(MOONBEAM_FORK_ID);

        bytes32 onchainHash;
        {
            (
                address[] memory onchainTargets,
                uint256[] memory onchainValues,
                bytes[] memory onchainCalldatas
            ) = governor.getProposalData(p.id);

            onchainHash = keccak256(
                abi.encode(onchainTargets, onchainValues, onchainCalldatas)
            );
        }

        assertEq(
            hash,
            onchainHash,
            string(
                abi.encodePacked(
                    "Hashes do not match for proposal ",
                    vm.toString(p.id)
                )
            )
        );
        console.log("Found onchain calldata for proposal: ", proposal.name());
    }

    /// @dev Split into four batches to avoid EVM memory allocation panic (0x41).
    /// Proposals >= 146 are excluded (heavy templates OOM even in tiny batches).
    function testMultichainGovernorCalldataMatchBatch1() public {
        ProposalFields[]
            memory multichainGovernorProposals = filterByGovernorAndProposalType(
                "MultichainGovernor",
                "HybridProposal"
            );
        for (uint256 i = multichainGovernorProposals.length; i > 0; i--) {
            uint256 id = multichainGovernorProposals[i - 1].id;
            if (_isExcludedMultichain(id) || id > 58) continue;
            _verifyMultichainProposal(multichainGovernorProposals[i - 1]);
        }
    }

    function testMultichainGovernorCalldataMatchBatch2() public {
        ProposalFields[]
            memory multichainGovernorProposals = filterByGovernorAndProposalType(
                "MultichainGovernor",
                "HybridProposal"
            );
        for (uint256 i = multichainGovernorProposals.length; i > 0; i--) {
            uint256 id = multichainGovernorProposals[i - 1].id;
            if (_isExcludedMultichain(id) || id <= 58 || id > 104) continue;
            _verifyMultichainProposal(multichainGovernorProposals[i - 1]);
        }
    }

    function testMultichainGovernorCalldataMatchBatch3() public {
        ProposalFields[]
            memory multichainGovernorProposals = filterByGovernorAndProposalType(
                "MultichainGovernor",
                "HybridProposal"
            );
        for (uint256 i = multichainGovernorProposals.length; i > 0; i--) {
            uint256 id = multichainGovernorProposals[i - 1].id;
            if (_isExcludedMultichain(id) || id <= 104 || id > 131) continue;
            _verifyMultichainProposal(multichainGovernorProposals[i - 1]);
        }
    }

    function testMultichainGovernorCalldataMatchBatch4() public {
        ProposalFields[]
            memory multichainGovernorProposals = filterByGovernorAndProposalType(
                "MultichainGovernor",
                "HybridProposal"
            );
        for (uint256 i = multichainGovernorProposals.length; i > 0; i--) {
            uint256 id = multichainGovernorProposals[i - 1].id;
            if (_isExcludedMultichain(id) || id <= 131) continue;
            _verifyMultichainProposal(multichainGovernorProposals[i - 1]);
        }
    }

    function testArtemisGovernorCalldataMatchHybridProposal() public {
        ProposalFields[]
            memory artemisGovernorProposals = filterByGovernorAndProposalType(
                "ArtemisGovernor",
                "HybridProposal"
            );
        for (uint256 i = artemisGovernorProposals.length; i > 0; i--) {
            // exclude proposals that are not onchain yet or proposal ID 127 (mip-x34)
            if (
                artemisGovernorProposals[i - 1].id == 0 ||
                artemisGovernorProposals[i - 1].id == 127
            ) {
                continue;
            }

            setEnv(artemisGovernorProposals[i - 1].envPath);

            string memory proposalPath = artemisGovernorProposals[i - 1].path;

            HybridProposal proposal = HybridProposal(deployCode(proposalPath));
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.initProposal(addresses);
            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                bytes[] memory calldatas
            ) = proposal.getTargetsPayloadsValues(addresses);
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            cleanEnv(artemisGovernorProposals[i - 1].envPath);

            vm.selectFork(MOONBEAM_FORK_ID);

            bytes32 onchainHash;
            {
                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    ,
                    bytes[] memory onchainCalldatas
                ) = artemisGovernor.getActions(
                        artemisGovernorProposals[i - 1].id
                    );

                onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );
            }

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal ",
                        vm.toString(artemisGovernorProposals[i - 1].id)
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }

    function testArtemisGovernorCalldataMatchGovernanceProposal() public {
        ProposalFields[]
            memory artemisGovernorProposals = filterByGovernorAndProposalType(
                "ArtemisGovernor",
                "GovernanceProposal"
            );
        for (uint256 i = artemisGovernorProposals.length; i > 0; i--) {
            // exclude proposals that are not onchain yet or proposal ID 127 (mip-x34)
            if (
                artemisGovernorProposals[i - 1].id == 0 ||
                artemisGovernorProposals[i - 1].id == 127
            ) {
                continue;
            }

            setEnv(artemisGovernorProposals[i - 1].envPath);

            string memory proposalPath = artemisGovernorProposals[i - 1].path;

            GovernanceProposal proposal = GovernanceProposal(
                deployCode(proposalPath)
            );
            vm.makePersistent(address(proposal));

            vm.selectFork(proposal.primaryForkId());

            proposal.initProposal(addresses);
            proposal.build(addresses);

            (
                address[] memory targets,
                uint256[] memory values,
                ,
                bytes[] memory calldatas
            ) = proposal._getActions();
            bytes32 hash = keccak256(abi.encode(targets, values, calldatas));

            cleanEnv(artemisGovernorProposals[i - 1].envPath);

            vm.selectFork(MOONBEAM_FORK_ID);

            bytes32 onchainHash;
            {
                (
                    address[] memory onchainTargets,
                    uint256[] memory onchainValues,
                    ,
                    bytes[] memory onchainCalldatas
                ) = artemisGovernor.getActions(
                        artemisGovernorProposals[i - 1].id
                    );

                onchainHash = keccak256(
                    abi.encode(onchainTargets, onchainValues, onchainCalldatas)
                );
            }

            assertEq(
                hash,
                onchainHash,
                string(
                    abi.encodePacked(
                        "Hashes do not match for proposal ",
                        vm.toString(artemisGovernorProposals[i - 1].id)
                    )
                )
            );
            console.log(
                "Found onchain calldata for proposal: ",
                proposal.name()
            );
        }
    }
}

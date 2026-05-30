pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Constants} from "@protocol/governance/multichain/Constants.sol";
import {SnapshotInterface} from "@protocol/governance/multichain/SnapshotInterface.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

/// @notice Test-only harness that restores functions removed from MultichainGovernor
/// to stay under the 24 KB contract-size limit on Moonbeam.
/// These functions are needed by the test suite but not by the on-chain deployment.
/// This harness can be removed once the Ethereum mainnet migration is complete.
contract MockMultichainGovernor is MultichainGovernor {
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice struct containing initializer data (removed from prod to save size)
    struct InitializeData {
        address well;
        address xWell;
        address stkWell;
        address distributor;
        uint256 proposalThreshold;
        uint256 votingPeriodSeconds;
        uint256 crossChainVoteCollectionPeriod;
        uint256 quorum;
        uint256 maxUserLiveProposals;
        uint128 pauseDuration;
        address pauseGuardian;
        address breakGlassGuardian;
        address wormholeRelayer;
    }

    /// @notice initialize the governor contract (removed from prod to save size)
    function initialize(
        InitializeData memory initData,
        WormholeTrustedSender.TrustedSender[] memory trustedSenders,
        bytes[] calldata calldatas
    ) external initializer {
        xWell = xWELL(initData.xWell);
        well = SnapshotInterface(initData.well);
        stkWell = SnapshotInterface(initData.stkWell);
        distributor = SnapshotInterface(initData.distributor);

        _setProposalThreshold(initData.proposalThreshold);
        _setVotingPeriod(initData.votingPeriodSeconds);
        _setCrossChainVoteCollectionPeriod(
            initData.crossChainVoteCollectionPeriod
        );
        _setQuorum(initData.quorum);
        _setMaxUserLiveProposals(initData.maxUserLiveProposals);
        _setBreakGlassGuardian(initData.breakGlassGuardian);

        __Pausable_init();

        _updatePauseDuration(initData.pauseDuration);

        /// set the pause guardian
        _grantGuardian(initData.pauseGuardian);

        _setWormholeRelayer(address(initData.wormholeRelayer));

        /// sets vote collection contracts
        _addTargetAddresses(trustedSenders);

        _setGasLimit(Constants.MIN_GAS_LIMIT);

        unchecked {
            for (uint256 i = 0; i < calldatas.length; i++) {
                _updateApprovedCalldata(calldatas[i], true);
            }
        }
    }

    /// @notice returns all live proposals for a user (removed from prod to save size)
    function getUserLiveProposals(
        address user
    ) external view returns (uint256[] memory) {
        uint256[] memory userProposals = new uint256[](
            currentUserLiveProposals(user)
        );
        uint256[] memory allUserProposals = _userLiveProposals[user].values();
        uint256 userLiveProposalIndex = 0;

        unchecked {
            for (uint256 i = 0; i < allUserProposals.length; i++) {
                if (proposalActive(allUserProposals[i])) {
                    userProposals[userLiveProposalIndex] = allUserProposals[i];
                    userLiveProposalIndex++;
                }
            }
        }

        return userProposals;
    }

    /// @notice return the votes for a particular chain and proposal (removed from prod to save size)
    function chainAddressVotes(
        uint256 proposalId,
        uint16 wormholeChainId
    )
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes)
    {
        VoteCounts storage voteCounts = chainVoteCollectorVotes[
            wormholeChainId
        ][proposalId];
        forVotes = voteCounts.forVotes;
        againstVotes = voteCounts.againstVotes;
        abstainVotes = voteCounts.abstainVotes;
    }

    /// @notice updates the maximum user live proposals (removed from prod to save size)
    function updateMaxUserLiveProposals(
        uint256 newMaxLiveProposals
    ) external onlyGovernor {
        _setMaxUserLiveProposals(newMaxLiveProposals);
    }

    /// @notice set a gas limit for the relayer (removed from prod to save size)
    function setGasLimit(uint96 newGasLimit) external onlyGovernor {
        require(
            newGasLimit >= Constants.MIN_GAS_LIMIT,
            "MultichainGovernor: gas limit too low"
        );

        _setGasLimit(newGasLimit);
    }

    // ---- Original mock helpers ----

    function newFeature() external pure returns (uint256) {
        return 1;
    }

    function proposalValid(uint256 proposalId) external view returns (bool) {
        return
            proposalCount >= proposalId &&
            proposalId > 0 &&
            proposals[proposalId].proposer != address(0);
    }

    function userHasProposal(
        uint256 proposalId,
        address proposer
    ) external view returns (bool) {
        return _userLiveProposals[proposer].contains(proposalId);
    }

    /// @notice returns information on a proposal in a struct format
    /// @param proposalId the id of the proposal to check
    function proposalInformationStruct(
        uint256 proposalId
    ) external view returns (ProposalInformation memory proposalInfo) {
        Proposal storage proposal = proposals[proposalId];

        proposalInfo.proposer = proposal.proposer;
        proposalInfo.voteSnapshotTimestamp = proposal.voteSnapshotTimestamp;
        proposalInfo.votingStartTime = proposal.votingStartTime;
        proposalInfo.votingEndTime = proposal.votingEndTime;
        proposalInfo.crossChainVoteCollectionEndTimestamp = proposal
            .crossChainVoteCollectionEndTimestamp;
        proposalInfo.totalVotes = proposal.totalVotes;
        proposalInfo.forVotes = proposal.forVotes;
        proposalInfo.againstVotes = proposal.againstVotes;
        proposalInfo.abstainVotes = proposal.abstainVotes;
    }
}

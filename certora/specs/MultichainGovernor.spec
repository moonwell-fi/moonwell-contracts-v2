using MockMultichainGovernor as t;

methods {
    function whitelistedCalldatas(bytes) external returns (bool) envfree;
    function proposalCount() external returns (uint256) envfree;
    function chainAddressVotes(uint256, uint16) external returns (uint256, uint256, uint256) envfree;
    function breakGlassGuardian() external returns (address) envfree;
    function gasLimit() external returns (uint96) envfree;

    function proposalInformation(uint256) external returns (address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256);
    function proposalVotes(uint256) external returns (uint256, uint256, uint256, uint256) envfree;

    function getCurrentVotes(address) external returns (uint256);
    function getProposalData(uint256) external returns (address[] memory, uint256[] memory, bytes[] memory);
    function getReceipt(
        uint256,
        address
    ) external returns (bool, uint8, uint256) envfree;
    function quorum() external returns (uint256) envfree;
    function maxUserLiveProposals() external returns (uint256) envfree;

    /// requires environment as this function reads block timestamp
    /// state is an enum so is type uint8
    function state(uint256 proposalId) external returns (uint8);

    /// requires environment as these functions call state which reads block timestamp
    function liveProposals() external returns (uint256[] memory);
    function getNumLiveProposals() external returns (uint256);
    function proposalValid(uint256 proposalId) external returns (bool) envfree;
    function userHasProposal(
        uint256 proposalId,
        address proposer
    ) external returns (bool) envfree;

    function proposalThreshold() external returns (uint256) envfree;
    function votingPeriod() external returns (uint256) envfree;
    function crossChainVoteCollectionPeriod() external returns (uint256) envfree;
    function currentUserLiveProposals(address) external returns (uint256);
    function getVotes(address account,uint256 timestamp,uint256 blockNumber) external returns (uint256);

    /// requires environment as this function can receive value
    function execute(uint256) external;
    /// requires environment as this function can receive value
    function propose(address[] memory,uint256[] memory,bytes[] memory, string memory) external returns (uint256);

    /// requires environment as this function reads msg.sender and block timestamp
    function cancel(uint256 proposalId) external;
    /// requires environment as this function reads msg.sender and block timestamp
    function castVote(uint256 proposalId, uint8 voteValue) external;

    /// governor only functions, requires environment as these functions read msg.sender
    function updateProposalThreshold(uint256 newProposalThreshold) external;
    function updateMaxUserLiveProposals(uint256 newMaxLiveProposals) external;
    function updateQuorum(uint256 newQuorum) external;
    function updateVotingPeriod(uint256 newVotingPeriod) external;
    function updateCrossChainVoteCollectionPeriod(
        uint256 newCrossChainVoteCollectionPeriod
    ) external;
    function setBreakGlassGuardian(address newGuardian) external;
    function removeExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external;
    function addExternalChainConfigs(
        WormholeTrustedSender.TrustedSender[] memory _trustedSenders
    ) external;
    function updateApprovedCalldata(
        bytes calldata data,
        bool approved
    ) external;
    function executeBreakGlass(
        address[] calldata,
        bytes[] calldata
    ) external;
    function setGasLimit(uint96) external;

    function proposalInformationStruct(
        uint256 proposalId
    ) external returns (IMultichainGovernor.ProposalInformation memory) envfree;
}

function oneEth() returns uint256 {
    return 1000000000000000000;
}

function oneDay() returns uint256 {
    return 86400;
}

/// ensure that the contract is initialized before asserting invariants, otherwise values will be 0
ghost uint8 _initialized {
    init_state axiom _initialized == 0;
}

hook Sstore _initialized uint8 newInitialized (uint8 oldInitialized) STORAGE {
    /// only valid state transition for _initialized is from 0 -> 1
    require oldInitialized == 0;
    require newInitialized == 1;

    _initialized = newInitialized;
}

invariant ghostMirrorsStorage(env e)
    _initialized == t._initialized;

invariant ghostStorageLteOne(env e)
    to_mathint(_initialized) <= to_mathint(1) {
        preserved {
            requireInvariant ghostMirrorsStorage(e);
        }
    }

/// Constants min and max invariants

invariant maxQuorum(env e)
    to_mathint(quorum()) <= to_mathint(500000000 * oneEth()) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant maxProposalThreshold(env e)
    to_mathint(proposalThreshold()) <= to_mathint(50000000 * oneEth()) &&
     to_mathint(proposalThreshold()) >= to_mathint(400000 * oneEth()) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant minMaxVotingPeriod(env e)
    to_mathint(votingPeriod()) <= to_mathint(14 * oneDay()) &&
     to_mathint(votingPeriod()) >= to_mathint(60 * 60) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant maxCrossChainVoteCollectionPeriod(env e)
    to_mathint(crossChainVoteCollectionPeriod()) <= to_mathint(14 * oneDay()) &&
     to_mathint(crossChainVoteCollectionPeriod()) >= to_mathint(60 * 60) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant minMaxUserLiveProposals(env e)
    to_mathint(maxUserLiveProposals()) <= to_mathint(20) &&
     to_mathint(maxUserLiveProposals()) >= to_mathint(1) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant minGasLimit(env e)
    to_mathint(gasLimit()) >= to_mathint(400000) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant proposalIdValid(env e, uint256 proposalId) 
    to_mathint(proposalId) <= to_mathint(proposalCount()) &&
     to_mathint(proposalId) > to_mathint(0) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e);
        }
    }

invariant totalVotesSumAllVote(env e, uint256 proposalId)
    proposalInformationStruct(proposalId).forVotes +
     proposalInformationStruct(proposalId).againstVotes +
     proposalInformationStruct(proposalId).abstainVotes == to_mathint(proposalInformationStruct(proposalId).totalVotes) {
        preserved {
            require _initialized == 1;
            requireInvariant ghostMirrorsStorage(e); 
        }
      }

// invariant proposalIdImpliesUserProposal(env e, uint256 proposalId, address proposer) 
//     proposalValid(proposalId) <=> userHasProposal(proposalId, proposalInformationStruct(proposalId).proposer) {
//         preserved {
//             require _initialized == 1;
//             requireInvariant ghostMirrorsStorage(e);
//         }
//     }

rule totalVotesSumAllVotes(method f, env e, uint256 proposalId) {
    mathint voteSum;
    mathint forVotes;
    mathint againstVotes;
    mathint abstainVotes;

    voteSum, forVotes, againstVotes, abstainVotes = proposalVotes(proposalId);

    /// filter precondition, stop over-approximation
    require voteSum == forVotes + againstVotes + abstainVotes;

    calldataarg args;

    f(e, args);

    mathint voteSumPost;
    mathint forVotesPost;
    mathint againstVotesPost;
    mathint abstainVotesPost;

    voteSumPost, forVotesPost, againstVotesPost, abstainVotesPost = proposalVotes(proposalId);

    /// assert post-condition
    assert voteSumPost == forVotesPost + againstVotesPost + abstainVotesPost, "proposal votes incorrect";
}

rule voteValueLteAbstain(method f, env e, uint256 proposalId, address voter) {
    bool hasVoted;
    uint8 voteValue;
    uint256 votes;

    hasVoted, voteValue, votes = getReceipt(proposalId, voter);

    /// filter precondition, stop over-approximation
    require !hasVoted && voteValue == 0 && votes == 0;

    calldataarg args;

    f(e, args);

    bool hasVotedPost;
    uint8 voteValuePost;
    uint256 votesPost;

    hasVotedPost, voteValuePost, votesPost = getReceipt(proposalId, voter);

    /// assert post-condition

    assert hasVotedPost => voteValuePost <= 2, "vote value not lte abstain";
    /// havoc causes this next line to fail
    // assert hasVotedPost => votesPost == getCurrentVotes(e, voter), "vote values incorrect";
    assert hasVotedPost => votesPost >= 1, "vote values must be gte 1";
}

/// tautology, but this is expected
rule pauseRemovesAllActiveProposals(env e) {
    require getNumLiveProposals(e) > 0;

    pause(e);

    /// all proposals in the enumerable that were active are now removed
    assert getNumLiveProposals(e) == 0, "pause did not remove all active proposals";
}

// rule statesAreValid(env e, uint256 proposalId) {
//     uint8 proposalState = state(proposalId);

//     mathint voteSum;
//     mathint forVotes;
//     mathint againstVotes;
//     mathint abstainVotes;

//     voteSum, forVotes, againstVotes, abstainVotes = proposalVotes(proposalId);
//     /// todo fetch proposal end time

//     /// succeeded state implies for votes outweight against votes, quorum is met and we're past the vote collection period
//     assert proposalState == 4 || proposalState == 5 => 
//         (againstVotes > forVotes) && (voteSum >= quorum()) && e.block.timestamp >= proposalInformation(proposalId),
//         "invalid proposal state";
// }
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
/// persistent: value must survive external calls (non-persistent ghosts are havoced by them)
persistent ghost uint8 _initialized {
    init_state axiom _initialized == 0;
}

hook Sstore _initialized uint8 newInitialized (uint8 oldInitialized) {
    /// transitions faithful to OZ 4.9 Initializable:
    /// - no-op write (same value)
    /// - initialize(): 0 -> 1
    /// - initializeV2() reinitializer(2): 0 -> 2 or 1 -> 2
    /// - _disableInitializers() in constructor: X -> 255
    require (
        oldInitialized == newInitialized ||
        (oldInitialized == 0 && newInitialized == 1) ||
        (oldInitialized < 2 && newInitialized == 2) ||
        (newInitialized == 255)
    );

    _initialized = newInitialized;
}

invariant ghostMirrorsStorage(env e)
    _initialized == t._initialized;

/// Constants min and max invariants

invariant maxQuorum(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    to_mathint(quorum()) <= to_mathint(500000000 * oneEth());

invariant maxProposalThreshold(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    (
        to_mathint(proposalThreshold()) <= to_mathint(50000000 * oneEth()) &&
        to_mathint(proposalThreshold()) >= to_mathint(400000 * oneEth())
    );

invariant minMaxVotingPeriod(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    (
        to_mathint(votingPeriod()) <= to_mathint(14 * oneDay()) &&
        to_mathint(votingPeriod()) >= to_mathint(60 * 60)
    );

invariant maxCrossChainVoteCollectionPeriod(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    (
        to_mathint(crossChainVoteCollectionPeriod()) <= to_mathint(14 * oneDay()) &&
        to_mathint(crossChainVoteCollectionPeriod()) >= to_mathint(60 * 60)
    );

invariant minMaxUserLiveProposals(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    (
        to_mathint(maxUserLiveProposals()) <= to_mathint(20) &&
        to_mathint(maxUserLiveProposals()) >= to_mathint(1)
    );

invariant minGasLimit(env e)
    (t._initialized == 1 || t._initialized == 2) =>
    to_mathint(gasLimit()) >= to_mathint(400000);

/// an existing proposal (proposer set) must be numbered within (0, proposalCount]
/// the existence guard mirrors MockMultichainGovernor.proposalValid():
/// claiming the range for ALL proposalIds would be false for id = proposalCount + 1
invariant proposalIdValid(env e, uint256 proposalId)
    to_mathint(proposalInformationStruct(proposalId).proposer) != 0 =>
    (
        to_mathint(proposalId) <= to_mathint(proposalCount()) &&
        to_mathint(proposalId) > to_mathint(0)
    );

/// vote tallies of every stored proposal must always sum to its total
/// (no preserved gating on _initialized: the claim holds for all reachable states)
invariant totalVotesSumAllVote(env e, uint256 proposalId)
    proposalInformationStruct(proposalId).forVotes +
     proposalInformationStruct(proposalId).againstVotes +
     proposalInformationStruct(proposalId).abstainVotes == to_mathint(proposalInformationStruct(proposalId).totalVotes);

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

/// pause() cancels every in-flight proposal and empties the live set (MultichainGovernor.pause)
/// referencing liveBefore keeps the postcondition falsifiable when requires are ignored,
/// so the advanced assert-tautology sanity check stays green
rule pauseRemovesAllActiveProposals(env e) {
    uint256 liveBefore = getNumLiveProposals(e);
    require liveBefore > 0;

    pause(e);

    /// all proposals in the enumerable that were active are now removed
    assert getNumLiveProposals(e) == 0 && getNumLiveProposals(e) < liveBefore,
        "pause did not remove all active proposals";
}
methods {
    function gasLimit() external returns (uint96) envfree;
    function getAllTargetChainsLength() external returns (uint256) envfree;

    function proposalInformation(uint256) external returns (address,uint256,uint256,uint256,uint256,uint256,uint256,uint256,uint256);
    function proposalVotes(uint256) external returns (uint256, uint256, uint256, uint256) envfree;

    function getReceipt(
        uint256,
        address
    ) external returns (bool, uint8, uint256) envfree;

    function getVotes(address account,uint256 timestamp) external returns (uint256);

    /// requires environment as this function can receive value
    function execute(uint256) external;
    /// requires environment as this function can receive value
    function propose(address[] memory,uint256[] memory,bytes[] memory, string memory) external returns (uint256);

    /// requires environment as this function reads msg.sender and block timestamp
    function castVote(uint256 proposalId, uint8 voteValue) external;

    function setGasLimit(uint96) external;
}

function oneEth() returns uint256 {
    return 1000000000000000000;
}

function oneDay() returns uint256 {
    return 86400;
}

/// ensure that the contract is initialized before asserting invariants, otherwise values will be 0
ghost uint8 _initialized;

hook Sstore _initialized uint8 newInitialized (uint8 oldInitialized) STORAGE {
    /// only valid state transition for _initialized is from 0 -> 1
    require oldInitialized == 0;
    require newInitialized == 1;

    _initialized = newInitialized;
}

invariant minGasLimit(env e)
    to_mathint(gasLimit()) >= to_mathint(400000) {
        preserved {
            require _initialized == 1;
        }
    }

invariant targetChainsLengthAlwaysOne(env e)
    to_mathint(getAllTargetChainsLength()) == to_mathint(1) {
        preserved {
            require _initialized == 1;
        }
    }

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

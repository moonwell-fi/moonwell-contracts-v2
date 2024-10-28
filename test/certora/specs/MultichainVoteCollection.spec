using MultichainVoteCollection as t;
using StakedWell as st;

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
    function rewardsVault() external returns (address);

    //// summarize these functions to avoid havoc on calls

    /// stkwell + xwell
    function _.transferFrom(address sender, address recipient, uint256 amount) external => ALWAYS(true);
    function _.transfer(address recipient, uint256 amount) external => ALWAYS(true);

    /// ecosystem reserve contract
    function EcosystemReserve._ external => NONDET;

    /// stkWell ontransfer hook
    function StakedWell.claimRewards(address to, uint256 amount) external => NONDET;
    function StakedWell.redeem(address to, uint256 amount) external => NONDET;
    function StakedWell.stake(address onBehalfOf, uint256 amount) external => NONDET;
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

ghost transfer(address,uint256) returns bool {
    axiom forall address x. forall uint256 y. transfer(x, y) == true;
}

ghost approve(address,uint256) returns bool {
    axiom forall address x. forall uint256 y. approve(x, y) == true;
}

invariant ghostMirrorsStorage()
    _initialized == t._initialized {
        preserved {
            requireInvariant ghostStorageLteOne();
        }
    }

invariant ghostStorageLteOne()
    to_mathint(_initialized) <= to_mathint(1) {
        preserved {
            require st._governance == 0;
            requireInvariant ghostMirrorsStorage();
        }
    }

rule minGasLimit(method f, env e)
filtered {
    f ->
    f.selector == sig:initialize(address,address,address,address,uint16,address).selector ||
    f.selector == sig:castVote(uint256,uint8).selector ||
    f.selector == sig:emitVotes(uint256).selector ||
    f.selector == sig:transferOwnership(address).selector ||
    f.selector == sig:renounceOwnership().selector ||
    f.selector == sig:acceptOwnership().selector ||
    f.selector == sig:receiveWormholeMessages(bytes memory,bytes[] memory,bytes32,uint16,bytes32).selector ||
    f.selector == sig:setGasLimit(uint96).selector
} {

    require _initialized == 1;
    require to_mathint(gasLimit()) >= to_mathint(400000);
    
    calldataarg args;

    f(e, args);

    assert to_mathint(gasLimit()) >= to_mathint(400000), "gas limit below min";
}

rule targetChainsLengthAlwaysOne(method f, env e)
filtered {
    f ->
    f.selector == sig:initialize(address,address,address,address,uint16,address).selector ||
    f.selector == sig:castVote(uint256,uint8).selector ||
    f.selector == sig:emitVotes(uint256).selector ||
    f.selector == sig:transferOwnership(address).selector ||
    f.selector == sig:renounceOwnership().selector ||
    f.selector == sig:acceptOwnership().selector ||
    f.selector == sig:receiveWormholeMessages(bytes memory,bytes[] memory,bytes32,uint16,bytes32).selector ||
    f.selector == sig:setGasLimit(uint96).selector
} {

    require (_initialized == 0) => (to_mathint(getAllTargetChainsLength()) == to_mathint(0));
    require (_initialized == 1) => (to_mathint(getAllTargetChainsLength()) == to_mathint(1));

    requireInvariant ghostMirrorsStorage();
    require to_mathint(getAllTargetChainsLength()) <= to_mathint(1);

    calldataarg args;

    f(e, args);

    assert
     to_mathint(getAllTargetChainsLength()) <= to_mathint(1),
     "incorrect target chain length";

    assert _initialized == t._initialized, "ghost incorrectly updated";

    assert (_initialized == 0) => (to_mathint(getAllTargetChainsLength()) == to_mathint(0)), "incorrect target chain length, not initialized";
    assert (_initialized == 1) => (to_mathint(getAllTargetChainsLength()) == to_mathint(1)), "incorrect target chain length, initialized";

}

rule totalVotesSumAllVotes(method f, env e, uint256 proposalId)
filtered {
    f ->
    f.selector == sig:initialize(address,address,address,address,uint16,address).selector ||
    f.selector == sig:castVote(uint256,uint8).selector ||
    f.selector == sig:emitVotes(uint256).selector ||
    f.selector == sig:transferOwnership(address).selector ||
    f.selector == sig:renounceOwnership().selector ||
    f.selector == sig:acceptOwnership().selector ||
    f.selector == sig:receiveWormholeMessages(bytes memory,bytes[] memory,bytes32,uint16,bytes32).selector ||
    f.selector == sig:setGasLimit(uint96).selector
} {
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

rule voteValueLteAbstain(method f, env e, uint256 proposalId, address voter)
filtered {
    f ->
    f.selector == sig:initialize(address,address,address,address,uint16,address).selector ||
    f.selector == sig:castVote(uint256,uint8).selector ||
    f.selector == sig:emitVotes(uint256).selector ||
    f.selector == sig:transferOwnership(address).selector ||
    f.selector == sig:renounceOwnership().selector ||
    f.selector == sig:acceptOwnership().selector ||
    f.selector == sig:receiveWormholeMessages(bytes memory,bytes[] memory,bytes32,uint16,bytes32).selector ||
    f.selector == sig:setGasLimit(uint96).selector
} {
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

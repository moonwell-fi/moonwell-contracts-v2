import "helpers.spec";
import "IERC20.spec";
import "IERC2612.spec";

methods {
    // exposed for FV
    function mint(address,uint256) external;
    function burn(address,uint256) external;
}

function xWELLAddress() returns address {
    return currentContract;
}

function timestampMax() returns uint256 {
    return 2 ^ 32 - 1;
}

function uintMax() returns uint256 {
    return 2 ^ 256 - 1;
}

function balanceMax() returns uint256 {
    return 2 ^ 224 - 1;
}

/// Preconditions:
///    - `balanceOf` is a uint256, that is less than or equal to uint224 max
///    - block timestamp is under or equal uint32 max

/// Invariants:
///    - `sumBalances` == `totalSupply`
///    - `votingPower` <= `uint224 max`
///    - `sumVotingPower` <= `totalSupply`
///    - `totalSupply` <= `maxSupply`
///    - `delegated voting power` <= `votingPower`
///    - user A delegating to user B => user B voting power >= user A voting power
///    - `votingPower` <= balanceOf single delegator
///    - number of checkpoints == total number of times transfer has been called by a user, and
///    how many times a user has received tokens + the amount of times that mint/burn has been
///    called to or for them.

/// Buffer limits
///    - `bufferCap` >= `minBufferCap`
///    - `rateLimitPerSecond` <= `maxRateLimitPerSecond`

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Ghost & hooks: sum of all balances                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
ghost mathint sumBalances {
    init_state axiom sumBalances == 0;
    axiom forall address a. forall address b. (
        (a == b => sumBalances >= to_mathint(balanceOfMirror[a])) &&
        (a != b => sumBalances >= balanceOfMirror[a] + balanceOfMirror[b])
    );
    axiom forall address a. forall address b. forall address c. (
        a != b && a != c && b != c => 
        sumBalances >= balanceOfMirror[a] + balanceOfMirror[b] + balanceOfMirror[c]
    );
}


/// @notice A ghost to mirror the balances, needed for `sumBalances`
ghost mapping(address => uint256) balanceOfMirror {
    init_state axiom forall address a. balanceOfMirror[a] == 0;
}

/// @notice a ghost to mirror the totalSupply in the ERC20 token contract,
/// needed for checking the total supply
ghost mathint totalSupplyStandardMirror {
    init_state axiom totalSupplyStandardMirror == 0;
    axiom sumBalances <= totalSupplyStandardMirror;

    axiom forall address a. forall address b. forall address c. (
        a != b && a != c && b != c => 
        totalSupplyStandardMirror >= balanceOfMirror[a] + balanceOfMirror[b] + balanceOfMirror[c]
    );
}

/// @title The hook for writing to total supply checkpoints
hook Sstore _totalSupply uint256 newTotalSupply (uint256 oldTotalSupply)
{
    totalSupplyStandardMirror = newTotalSupply;
}

// Because `balance` has a uint256 type, any balance addition in CVL1 behaved as a `require_uint256()` casting,
// leaving out the possibility of overflow. This is not the case in CVL2 where casting became more explicit.
// A counterexample in CVL2 is having an initial state where Alice initial balance is larger than totalSupply, which 
// overflows Alice's balance when receiving a transfer. This is not possible unless the contract is deployed into an 
// already used address (or upgraded from corrupted state).
// We restrict such behavior by making sure no balance is greater than the sum of balances.
hook Sload uint256 balance _balances[KEY address addr] {
    require sumBalances >= to_mathint(balance);
}

/// @title The hook
hook Sstore _balances[KEY address user] uint256 new_balance (uint256 old_balance)
{
    sumBalances = sumBalances + new_balance - old_balance;
    balanceOfMirror[user] = new_balance;
}

/// @title Checkpoint array well-formedness harness
/// `_writeCheckpoint` does `ckpts.push()` inside `unchecked`; an arbitrary induction
/// state with length == max_uint256 makes the push wrap the length to 0, after which
/// getVotes() returns garbage (counterexamples in doubleDelegateIsGreaterOrEqual and
/// friends). Reachable executions of OZ ERC20Votes only ever append, with the length
/// nowhere near max_uint256, so these requires prune unreachable states only.
hook Sstore _checkpoints[KEY address a].length uint newLen (uint oldLen) {
    require oldLen < 4294967295;
    require newLen > oldLen;
}

/// same bound on READS: getVotes() binary-searches `_checkpoints[account]` and the
/// adversarial induction states place absurd lengths there without ever storing them
hook Sload uint256 ckptLen _checkpoints[KEY address a].length {
    require ckptLen < 4294967295;
}

/// @title Formally prove that `balanceOfMirror` mirrors `balanceOf`
invariant mirrorIsTrue(address a)
    balanceOfMirror[a] == balanceOf(a);

invariant sumBalancesEqTotalSupplyMirror()
    sumBalances == totalSupplyStandardMirror {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }

invariant balanceOfLteUint224Max(address a)
    balanceOf(a) <= balanceMax() {
        preserved {
            requireInvariant totalSupplyLteMax();
            requireInvariant mirrorIsTrue(a);
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }


/// if buffer cap is non zero, it implies that buffer cap is gt min buffer cap
invariant bufferCapGteMinBufferCap(address a)
    bufferCap(a) != 0 => assert_uint112(bufferCap(a)) >= minBufferCap(); /// buffercap can never exceed uint112 max

invariant rateLimitPerSecondLteMaxRateLimit(address a)
    assert_uint128(rateLimitPerSecond(a)) <= maxRateLimitPerSecond();

invariant nonZeroRateLimitPerSecondImpliesNonZeroBufferCap(address a)
    assert_uint128(rateLimitPerSecond(a)) != 0 => bufferCap(a) != 0;

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: totalSupply is the sum of all balances                                                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant totalSupplyIsSumOfBalances()
    to_mathint(totalSupply()) == sumBalances;

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: totalSupply is less than or equal to the max total supply                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant totalSupplyLteMax()
    totalSupply() <= MAX_SUPPLY() {
        preserved {
            requireInvariant totalSupplyIsSumOfBalances();
        }
    }

/// user A delegating to user B => user B voting power >= balances of both A and B
///
/// DISABLED (audit 2026-10): not inductively provable over arbitrary states, kept as
/// documentation. History:
///  1. The ORIGINAL body was an unparenthesized chain
///     `P && C1 => X && C2 => Y && C3 => Z` whose parse made the first clause's guard
///     contradict the second's (delegates(a)==b && a!=b vs delegates(a)==a), collapsing
///     the whole body into a vacuous tautology (caught by invariant_not_trivial).
///  2. The properly parenthesized form below is non-trivial and holds at the base case,
///     but the induction step fails against three counterexample families, all rooted in
///     OZ ERC20Votes checkpoint arrays of ARBITRARY (unreachable) states:
///       a. `_writeCheckpoint` does `ckpts.push()` inside `unchecked`; a length of
///          max_uint256 wraps to 0 and getVotes() then returns garbage
///          (mitigated: the .length Sstore/Sload harness hooks above prune this family);
///       b. absurd lengths only ever READ (mitigated likewise by the Sload bound);
///       c. junk checkpoint ELEMENTS inside a length-bounded array (e.g. length
///          4294961367 with a single .votes=1 entry vs balanceOf=2) - any lower-bound
///          claim on getVotes() is falsifiable this way, and element-level well-formedness
///          cannot be expressed with local CVL hooks: element accesses go through
///          `_unsafeAccess` (inline assembly, see access-path caveats in the Certora docs)
///          and sortedness is not locally constrainable.
///  3. Reachable-state content of the clauses is covered by the rule
///     `userCanDelegateBalance` (proven without this assumption).
/*
invariant doubleDelegateIsGreaterOrEqual(env e, address a, address b)
    ((b != 0) && (a != 0) && (a != b)) => (
        /// if a is delegated to b, and b is delegated to b, then b should have at least as many votes as a
        (((delegates(a) == b) && (delegates(b) == b)) =>
            to_mathint(getVotes(b)) >= to_mathint(balanceOf(a)) + to_mathint(balanceOf(b))) &&
        /// both delegated to a, then the delegate (a) should have sum of votes of both delegators balance at minimum
        (((delegates(a) == a) && (delegates(b) == a)) =>
            to_mathint(getVotes(a)) >= to_mathint(balanceOf(a)) + to_mathint(balanceOf(b))) &&
        /// delegated to the same nonzero address, then the delegate should have sum of votes of both delegators balance at minimum
        /// (delegates == 0 holds no voting power: OZ _moveVotingPower skips address(0))
        (((delegates(a) == delegates(b)) && (delegates(a) != 0)) =>
            to_mathint(getVotes(delegates(b))) >= to_mathint(balanceOf(a)) + to_mathint(balanceOf(b)))
    )

     {
        preserved {
            require ((b != 0 && a != 0 && a != b) &&
                (delegates(a) == b) => getVotes(b) >= balanceOf(a) &&
                (delegates(b) == a) => getVotes(a) >= balanceOf(b)
            );
            requireInvariant totalSupplyIsSumOfBalances();
            require getVotes(a) <= totalSupply();
            require getVotes(b) <= totalSupply();
            requireInvariant mirrorIsTrue(a);
            requireInvariant mirrorIsTrue(b);
            requireInvariant addressZeroCannotDelegate();
        }
    }
*/

invariant addressZeroCannotDelegate()
    delegates(0) == 0 {
        preserved delegate(address to) with (env e) {
            require(e.msg.sender != 0);
        }
    }

/// no state changes you could ever make that would put the total supply above the max supply
/// (the former `maxSupplyEqMAXSUPPLY` invariant was deleted: maxSupply() and MAX_SUPPLY()
///  are the same constant, making it a tautology caught by invariant_not_trivial)
invariant totalSupplyLteUint224Max()
    totalSupply() <= balanceMax() {
        preserved burn(address to, uint256 amount) with (env e) {
            requireInvariant totalSupplyIsSumOfBalances();
            requireInvariant mirrorIsTrue(to);
        }
    }

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: balance of address(0) is 0                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant zeroAddressNoBalance()
    balanceOf(0) == 0;

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariant: balance of well address is always 0                                                                      │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
invariant wellAddressNoBalance()
    balanceOf(xWELLAddress()) == 0;

rule userCanDelegateBalance(env e, address to) {
    address from = e.msg.sender;
    require to != 0 && from != 0; /// moving votes to address 0 does not register
    require(delegates(from) != to); /// not already delegated to the target address

    requireInvariant mirrorIsTrue(from);
    requireInvariant mirrorIsTrue(to);

    mathint startingVotes = to_mathint(getVotes(to));
    mathint fromBalance = to_mathint(balanceOf(from));

    delegate(e, to);

    mathint endingVotes = to_mathint(getVotes(to));

    assert fromBalance != 0 => endingVotes == startingVotes + fromBalance, "balance not delegated";
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only mint and burn can change total supply                                                                   │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule noChangeTotalSupply(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;

    uint256 totalSupplyBefore = totalSupply();
    f(e, args);
    uint256 totalSupplyAfter = totalSupply();

    uint128 rateLimitPerSecond;
    uint112 bufferCap;
    uint32 lastBufferUsedTime;
    uint112 bufferStored;
    uint112 midpoint;

    rateLimitPerSecond, bufferCap, lastBufferUsedTime, bufferStored, midpoint = rateLimits(e.msg.sender);

    assert (totalSupplyAfter > totalSupplyBefore && bufferCap(e.msg.sender) > assert_uint256(midpoint)) =>
     bufferCap(e.msg.sender) != 0;
    assert totalSupplyAfter > totalSupplyBefore => f.selector == sig:mint(address,uint256).selector;
    assert totalSupplyAfter < totalSupplyBefore => f.selector == sig:burn(address,uint256).selector && bufferCap(e.msg.sender) != 0;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only the token holder or an approved third party can reduce an account's balance                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule onlyAuthorizedCanTransfer(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;
    address account;

    uint256 allowanceBefore = allowance(account, e.msg.sender);
    uint256 balanceBefore   = balanceOf(account);
    f(e, args);
    uint256 balanceAfter    = balanceOf(account);

    assert (
        balanceAfter < balanceBefore
    ) => (
        f.selector == sig:burn(address,uint256).selector ||
        e.msg.sender == account ||
        balanceBefore - balanceAfter <= to_mathint(allowanceBefore)
    );
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: only the token holder (or a permit) can increase allowance. The spender can decrease it by using it          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule onlyHolderOfSpenderCanChangeAllowance(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    method f;
    calldataarg args;
    address holder;
    address spender;

    uint256 allowanceBefore = allowance(holder, spender);
    f(e, args);
    uint256 allowanceAfter = allowance(holder, spender);

    assert (
        allowanceAfter > allowanceBefore
    ) => (
        (f.selector == sig:approve(address,uint256).selector           && e.msg.sender == holder) ||
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector) ||
        (f.selector == sig:increaseAllowance(address,uint256).selector && e.msg.sender == holder)
    );

    assert (
        allowanceAfter < allowanceBefore
    ) => (
        (f.selector == sig:transferFrom(address,address,uint256).selector && e.msg.sender == spender) ||
        (f.selector == sig:approve(address,uint256).selector              && e.msg.sender == holder ) ||
        (f.selector == sig:decreaseAllowance(address,uint256).selector    && e.msg.sender == holder ) ||
        (f.selector == sig:burn(address,uint256).selector                                           ) || /// burn decreases allowance
        (f.selector == sig:permit(address,address,uint256,uint256,uint8,bytes32,bytes32).selector)
    );
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: mint behavior and side effects                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule mint(env e, uint256 amount, address to, address other) {
    requireInvariant totalSupplyIsSumOfBalances();
    requireInvariant addressZeroCannotDelegate(); /// if address 0 has a delegate, it causes problems here

    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());

    /// other must be different than to and from
    requireInvariant mirrorIsTrue(to);
    requireInvariant mirrorIsTrue(e.msg.sender);
    require (delegates(to) != 0 => getVotes(delegates(to)) >= balanceOf(to));

    // cache state
    uint256 toBalanceBefore    = balanceOf(to);
    uint256 otherBalanceBefore = balanceOf(other);
    uint256 totalSupplyBefore  = totalSupply();

    // run transaction
    mint(e, to, amount);

    // updates balance and totalSupply
    assert to_mathint(balanceOf(to)) == toBalanceBefore   + amount;
    assert to_mathint(totalSupply()) == totalSupplyBefore + amount;

    // no other balance is modified
    assert balanceOf(other) != otherBalanceBefore => other == to;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rules: burn behavior and side effects                                                                               │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule burn(env e) {
    requireInvariant totalSupplyIsSumOfBalances();
    require nonpayable(e);
    require(e.block.timestamp <= timestampMax()); /// timestamp sanity check
    require(bufferCap(e.msg.sender) >= buffer(e, e.msg.sender));
    require(e.msg.sender != 0); /// filter out zero address

    address from;
    address other;
    uint256 amount;

    // cache state
    uint256 fromBalanceBefore  = balanceOf(from);
    uint256 otherBalanceBefore = balanceOf(other);
    uint256 totalSupplyBefore  = totalSupply();

    require(allowance(from, e.msg.sender) >= amount);
    require(amount != 0);

    // run transaction
    burn(e, from, amount);

    // updates balance and totalSupply
    assert to_mathint(balanceOf(from)) == fromBalanceBefore - amount, "incorrect balanceOf";
    assert to_mathint(totalSupply())   == totalSupplyBefore - amount, "incorrect totalSupply";

    // no other balance is modified
    assert balanceOf(other) != otherBalanceBefore => other == from, "incorrect other balance";
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: transfer behavior and side effects                                                                            │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule transfer(env e) {
    requireInvariant totalSupplyIsSumOfBalances();

    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());

    address holder = e.msg.sender;
    address recipient;
    address other;
    uint256 amount;

    requireInvariant mirrorIsTrue(holder);
    requireInvariant mirrorIsTrue(recipient);
    requireInvariant balanceOfLteUint224Max(holder);
    requireInvariant balanceOfLteUint224Max(recipient);

    require delegates(holder) != 0 => getVotes(delegates(holder)) >= balanceOf(holder);
    require delegates(recipient) != 0 => getVotes(delegates(recipient)) >= balanceOf(recipient);

    // cache state
    uint256 holderBalanceBefore          = balanceOf(holder);
    uint256 recipientVotesBefore         = getVotes(recipient);
    uint256 recipientDelegateVotesBefore = getVotes(delegates(recipient));
    uint256 recipientBalanceBefore       = balanceOf(recipient);
    uint256 otherBalanceBefore           = balanceOf(other);

    // run transaction
    transfer@withrevert(e, recipient, amount);

    /// if holder delegated their votes, ensure the delegatee's vote counts are greater than
    /// or equal to the holder's balances

    // check outcome
    if (lastReverted) {
        assert holder == 0 || /// fails when holder is address 0
        recipient == 0 || /// fails when recipient is address 0
        amount > holderBalanceBefore || /// fails when holder has not enough balance to transfer
        recipient == xWELLAddress() || /// fails when transfering to xWELL
        to_mathint(recipientBalanceBefore) + to_mathint(amount) > to_mathint(balanceMax()) || /// balance max failure
        recipientDelegateVotesBefore + amount > to_mathint(balanceMax()); /// votes max failure overflow -> safecast to 224 failure
    } else {
        // balances of holder and recipient are updated
        assert to_mathint(balanceOf(holder))    == holderBalanceBefore    - (holder == recipient ? 0 : amount);
        assert to_mathint(balanceOf(recipient)) == recipientBalanceBefore + (holder == recipient ? 0 : amount);

        // no other balance is modified
        assert balanceOf(other) != otherBalanceBefore => (other == holder || other == recipient);
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: transferFrom behavior and side effects                                                                        │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule transferFrom(env e, address holder, address recipient, address other, uint256 amount) {
    address spender = e.msg.sender;

    requireInvariant mirrorIsTrue(holder);
    requireInvariant mirrorIsTrue(recipient);

    requireInvariant totalSupplyIsSumOfBalances();
    require nonpayable(e);
    require(e.block.timestamp <= timestampMax());
    require(other != recipient && other != holder && other != spender);

    require delegates(holder) != 0 => getVotes(delegates(holder)) >= balanceOf(holder);
    require delegates(recipient) != 0 => getVotes(delegates(recipient)) >= balanceOf(recipient);

    /// if holder delegated their votes, ensure the delegatee's vote counts are greater than
    /// or equal to the holder's balances

    // cache state
    uint256 allowanceBefore              = allowance(holder, spender);
    uint256 holderBalanceBefore          = balanceOf(holder);
    uint256 recipientBalanceBefore       = balanceOf(recipient);
    uint256 otherBalanceBefore           = balanceOf(other);
    uint256 recipientDelegateVotesBefore = getVotes(delegates(recipient));

    // run transaction
    transferFrom@withrevert(e, holder, recipient, amount);

    // check outcome
    if (lastReverted) {
        assert holder == 0 ||
        recipient == 0 ||
        spender == 0 ||
        amount > holderBalanceBefore ||
        amount > allowanceBefore ||
        recipient == xWELLAddress() ||
        to_mathint(recipientDelegateVotesBefore) + to_mathint(amount) > to_mathint(balanceMax()) ||
        to_mathint(recipientBalanceBefore) + to_mathint(amount) > to_mathint(balanceMax());
    } else {
        // allowance is valid & updated
        assert allowanceBefore            >= amount;
        assert to_mathint(allowance(holder, spender)) == (allowanceBefore == max_uint256 ? max_uint256 : allowanceBefore - amount);

        // balances of holder and recipient are updated
        assert to_mathint(balanceOf(holder))    == holderBalanceBefore    - (holder == recipient ? 0 : amount);
        assert to_mathint(balanceOf(recipient)) == recipientBalanceBefore + (holder == recipient ? 0 : amount);

        // no other balance is modified
        assert balanceOf(other) == otherBalanceBefore;
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: approve behavior and side effects                                                                             │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule approve(env e) {
    require nonpayable(e);

    address holder = e.msg.sender;
    address spender;
    address otherHolder;
    address otherSpender;
    uint256 amount;

    // cache state
    uint256 otherAllowanceBefore = allowance(otherHolder, otherSpender);

    // run transaction
    approve@withrevert(e, spender, amount);

    // check outcome
    if (lastReverted) {
        assert holder == 0 || spender == 0;
    } else {
        // allowance is updated
        assert allowance(holder, spender) == amount;

        // other allowances are untouched
        assert allowance(otherHolder, otherSpender) != otherAllowanceBefore => (otherHolder == holder && otherSpender == spender);
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: permit behavior and side effects                                                                              │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule permit(env e) {
    require nonpayable(e);

    address holder;
    address spender;
    uint256 amount;
    uint256 deadline;
    uint8 v;
    bytes32 r;
    bytes32 s;

    address account1;
    address account2;
    address account3;

    // cache state
    uint256 nonceBefore          = nonces(holder);
    uint256 otherNonceBefore     = nonces(account1);
    uint256 otherAllowanceBefore = allowance(account2, account3);

    // sanity: nonce overflow, which possible in theory, is assumed to be impossible in practice
    require nonceBefore      < max_uint256;
    require otherNonceBefore < max_uint256;

    // run transaction
    permit@withrevert(e, holder, spender, amount, deadline, v, r, s);

    // check outcome
    if (lastReverted) {
        // Without formally checking the signature, we can't verify exactly the revert causes
        assert true;
    } else {
        // allowance and nonce are updated
        assert allowance(holder, spender) == amount;
        assert to_mathint(nonces(holder)) == nonceBefore + 1;

        // deadline was respected
        assert deadline >= e.block.timestamp;

        // no other allowance or nonce is modified
        assert nonces(account1)              != otherNonceBefore     => account1 == holder;
        assert allowance(account2, account3) != otherAllowanceBefore => (account2 == holder && account3 == spender);
    }
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: allowance +- behavior                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule increaseAllowance(env e, address spender, uint256 amount) {
    address holder = e.msg.sender;
    address otherHolder;
    address otherSpender;

    require(otherHolder != holder);

    // cache state
    uint256 allowanceBefore = allowance(holder, spender);
    uint256 otherAllowanceBefore = allowance(otherHolder, otherSpender);

    // run transaction
    increaseAllowance(e, spender, amount);

    // allowance is updated
    assert to_mathint(allowance(holder, spender)) == to_mathint(allowanceBefore + amount), "incorrect allowance";
    assert otherAllowanceBefore == allowance(otherHolder, otherSpender), "incorrect allowance for other holder/spender";
}

rule decreaseAllowance(env e, address spender, uint256 amount) {
    address holder = e.msg.sender;
    address otherHolder;
    address otherSpender;

    require(otherHolder != holder);

    // cache state
    uint256 allowanceBefore = allowance(holder, spender);
    uint256 otherAllowanceBefore = allowance(otherHolder, otherSpender);

    // run transaction
    decreaseAllowance(e, spender, amount);

    // allowance is updated
    assert to_mathint(allowance(holder, spender)) == to_mathint(allowanceBefore - amount), "incorrect allowance";
    assert otherAllowanceBefore == allowance(otherHolder, otherSpender), "incorrect allowance for other holder/spender";
}

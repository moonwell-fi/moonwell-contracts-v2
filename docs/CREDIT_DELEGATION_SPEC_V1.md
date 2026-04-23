# Credit Delegation Spec V1

## 0. How to read this doc

**What is self-contained here:**

- Problem statement and product shape
- All Moonwell interfaces you'll call into (mToken, Comptroller,
  ChainlinkOracle, TemporalGovernor) — signatures quoted inline in §3 and §17
- Full onchain data model (structs, storage, enums)
- All three EIP-712 signature schemes with type hashes
- Every external function signature
- Every event and custom error
- Flow pseudocode for the 6 main lifecycle paths
- Security considerations specific to this design
- Test harness shape (Foundry, forked Base)
- A 10-PR sequence for implementation

**What is not in this doc:**

- CLI / frontend / indexer work — those consume the contracts but are built
  separately
- Mainnet deployment choreography beyond a dry-run
- UX or agent SDK details

**Hard constraints:**

- OpenZeppelin contracts for `Ownable`, `Pausable`, `ReentrancyGuard`, `ECDSA`,
  `Clones`, `SafeERC20`
- No compiler version changes. No upgradability via a proxy on the factory (keep
  it simple and immutable after deploy — governance change = new deploy +
  migration)

---

## 1. Problem statement & product context

### 1.1 What problem this solves

Moonwell is an over-collateralized lending protocol (Compound v2 fork) on Base
and Optimism. An address can only borrow if it first supplies more than it wants
to borrow. This leaves two gaps:

1. **Agents (or humans) who hold tokens Moonwell doesn't list as collateral**
   (memecoins, LP tokens, long-tail assets) cannot borrow against them.
2. **Lenders with unused Moonwell borrow capacity** have no way to monetize that
   capacity beyond their own borrowing.

The Credit Marketplace lets an agent with unused Moonwell credit rent it to a
borrower who posts _non-Moonwell_ collateral into an onchain escrow, under terms
agreed by both sides and priced by an off-chain pricing engine.

This is the "pawn-store" model: the lender takes no principal risk if the
borrower's collateral is worth more than the loan (enforced **on-chain** via a
Chainlink LTV check at match time, plus over-seizure on missed payments), and
the borrower gets access to USDC without selling their illiquid asset.

A later phase (section 18) extends this to _undercollateralized_
reputation-backed borrowing, using a credit bureau built in the `lunar-indexer`
repo.

### 1.2 Who participates

| Role                  | Who                                                                                             | What they do onchain                                                                                                                                                         |
| --------------------- | ----------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Lender**            | An EOA or smart account with a Moonwell mToken position and unused borrow capacity              | Signs + posts an EIP-712 `Offer`; grants ERC20 approval on mTokens to the factory                                                                                            |
| **Borrower**          | An EOA or smart account holding a non-Moonwell token they want to use as collateral             | Signs + posts an EIP-712 `Request`; grants ERC20 approval on the collateral to the factory                                                                                   |
| **Backend**           | Off-chain service (lunar-indexer) operated by Moonwell, with a pricing engine and credit bureau | Signs EIP-712 `BackendTerms` that lock the final loan parameters (APR, schedule, grace, etc.) when a compatible offer+request pair exists, and submits the match transaction |
| **Temporal Governor** | Moonwell's cross-chain governance executor contract (see §3.5)                                  | Owns the factory; rotates backend signer; whitelists collateral + principal-token Chainlink feeds; unpauses after a guardian pause; rotates the pause guardian               |
| **Pause Guardian**    | Moonwell's security-response EOA/multisig (`chains/<id>.json::PAUSE_GUARDIAN`)                  | Can pause the factory immediately in an emergency. Cannot unpause, cannot change any other config. Rotated by the Temporal Governor.                                         |

### 1.3 Why onchain

The order book is onchain so:

- Anyone can index offers and requests (lunar-indexer does this) without
  permission
- Agents don't need to trust a centralized order book
- Settlement is atomic and verifiable — no "did the backend actually match me
  with the lender it claimed?"

Pricing (APR, schedule computation based on credit tier + market conditions)
lives off-chain in the backend. The backend's authority is limited to producing
signed terms; onchain logic enforces what it signed.

### 1.4 Product-level flow (human-readable)

```
1. Lender calls factory.postOffer(offer, sig)
   - Lender previously: approve(factory, mTokenAmount) on their mToken
2. Borrower calls factory.postRequest(request, sig)
   - Borrower previously: approve(factory, collateralAmount) on their collateral token
3. Backend notices a compatible offer+request pair. It computes canonical terms
   (APR, interest schedule, principal due date, grace period, over-seizure ratio,
   fee) based on market state + the borrower's credit tier.
4. Backend signs the EIP-712 BackendTerms and calls
   factory.createLoan(offer, request, backendTerms, offerSig, requestSig, backendSig)
5. Factory verifies all three signatures and nonces, checks bounds compatibility,
   deploys a fresh CreditLoan proxy clone, pulls mTokens from lender and collateral
   from borrower via transferFrom, calls clone.initialize(...) and clone.activate()
6. Clone enters markets, calls mToken.borrow(principal), sends principalToken (USDC)
   to borrower. Loan is now Active.
7. Borrower makes periodic interest payments to the clone via clone.makePayment()
8. If a payment is missed by more than gracePeriod, anyone can call
   clone.claimMissedPayment() — clone uses Chainlink oracle to seize
   (missedAmount × (1 + overSeizureBps)) worth of collateral, sends to lender
9. After consecutiveMissesForDefault (e.g. 2) missed payments, the loan accelerates:
   all remaining principal + accrued interest is immediately due. Remaining collateral
   is fully seizable by lender via clone.seizeAll()
10. If all payments land on schedule, borrower makes the final principal payment.
    Clone calls mToken.repayBorrowBehalf(clone, borrowBalance), returns lender's
    mTokens + their share of interest, returns borrower's residual collateral, sends
    the fee cut to feeRecipient. Loan is Settled.
```

---

## 2. Architectural shape

### 2.1 Two contracts per chain

```
                              ┌──────────────────────────────────┐
                              │    CreditMarketplaceFactory      │
                              │    (singleton per chain)         │
                              │                                  │
                              │  ├─ Order book (offers/requests) │
                              │  ├─ Admin config (owner =        │
                              │  │   Temporal Governor)          │
                              │  ├─ Backend signer registry      │
                              │  ├─ Collateral + mToken          │
                              │  │   whitelists + Chainlink feeds│
                              │  └─ createLoan() — deploys clones│
                              └──────────────┬───────────────────┘
                                             │
                                   Clones.clone() + initialize()
                                             │
                     ┌───────────────────────┼───────────────────────┐
                     ▼                       ▼                       ▼
              ┌──────────────┐        ┌──────────────┐        ┌──────────────┐
              │ CreditLoan A │        │ CreditLoan B │        │ CreditLoan C │
              │ (EIP-1167    │        │ (EIP-1167    │        │ (EIP-1167    │
              │  proxy)      │        │  proxy)      │        │  proxy)      │
              └──────┬───────┘        └──────┬───────┘        └──────┬───────┘
                     │ delegatecall to       │                       │
                     ▼                       ▼                       ▼
                  ┌────────────────────────────────────────────────────┐
                  │       CreditLoan Implementation (one per chain)    │
                  │       Contains: initialize, activate, makePayment, │
                  │       claimMissedPayment, seizeAll, settle, views  │
                  └────────────────────────────────────────────────────┘
```

- **`CreditMarketplaceFactory`** — holds the order book, admin config, and
  deploys per-loan proxies. `Ownable` by the Temporal Governor.
- **`CreditLoan`** (implementation) — the logic contract, deployed exactly once
  per chain. Has no state of its own in production use beyond the init guard on
  its own storage slots. Its `initialize` function is locked by the factory
  constructor to prevent direct-impl hijack.
- **`CreditLoan` clones** — EIP-1167 minimal-proxy clones of the implementation,
  deployed by the factory on every successful match. Each clone has its own
  storage (the loan's state) and `delegatecall`s to the shared implementation
  for logic.

### 2.2 Why this shape

Three alternatives were considered and rejected:

| Alternative                                          | Problem                                                                                               |
| ---------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Single factory contract holds all loans in a mapping | All lenders share Moonwell-position risk; one bad loan → cascading liquidation. Rejected.             |
| Lender submits the match tx themselves               | Requires lender to be online at match time; agents running 24/7 expect delegated execution. Rejected. |
| Per-lender proxy wallet                              | Too much first-time setup for lenders; complicates UX. Rejected.                                      |

**What the clone pattern buys:**

- **Risk isolation per match.** Each clone is its own account on Moonwell. If
  one loan's collateral value drops and Moonwell liquidates the clone's borrow,
  no other clone is affected.
- **Minimal gas overhead.** EIP-1167 clones are ~45 bytes; deploying one costs
  ~50k gas. Total match cost (including Moonwell interactions) is ~400–500k gas,
  which is fine for a multi-month loan origination.
- **Simple per-loan logic.** The `CreditLoan` contract doesn't need to manage a
  mapping of loans or dispatch calls — it only deals with its own single loan.
- **Immutable terms per loan.** Once initialized, the loan's terms are frozen in
  storage. No admin can retroactively change a loan's APR, schedule, or oracle
  feed.

### 2.3 Ownership

```solidity
// Factory
// ─────
// Inherits OpenZeppelin Ownable + OpenZeppelin Pausable.
// Owner is set in constructor to the Temporal Governor address for the chain.
// Admin functions are `onlyOwner`; `pause()` is `onlyOwnerOrGuardian`.

// CreditLoan implementation
// ─────────────────────────
// Not ownable — logic is immutable code.
// Factory constructor calls impl.initialize(...) with burner/sentinel values
// and sets initialized=true to prevent anyone from calling initialize on the
// impl address directly.

// CreditLoan clones
// ─────────────────
// Not ownable. Only callable parties are the lender (and sometimes the borrower
// and the backend, at specific lifecycle points — enforced via require checks).
// The factory has NO authority over a clone once it's activated. Governance
// parameter changes to the factory do NOT flow into existing clones.
// The pause guardian has NO authority over a clone (pause only gates the
// factory's match/post/cancel surface).
```

**Pause Guardian — role semantics**

A second principal, distinct from the Temporal Governor owner, holds a narrowly
scoped pause-only permission on the factory:

- Can call `pause()` (single tx, no delay).
- Cannot call `unpause()` — only the Temporal Governor can lift a pause.
- Cannot rotate itself — the Temporal Governor calls `setPauseGuardian`.
- Cannot touch any other admin surface (no signer rotation, no whitelisting, no
  param changes).
- Its pause is limited to the factory's origination + order-book surface
  (`createLoan`, `postOffer`, `postRequest`, `cancelOffer`, `cancelRequest`).
  Existing loans continue to operate (`makePayment`, `claimMissedPayment`,
  `seizeAll`, etc.) so borrowers can keep current during an incident.

This mirrors the existing Moonwell pattern in
`src/xWELL/ConfigurablePauseGuardian.sol`; the factory doesn't subclass it
(factory is plain `Ownable` + OZ `Pausable`, not a UUPS proxy) but copies the
role semantics so ops doesn't have to learn a new primitive. The reason for this
role is straightforward: the Temporal Governor path is a cross-chain Moonbeam →
Wormhole → Base proposal with a ~5-day delay, which is not a viable response
time for an acute exploit.

### 2.4 Governance actions

Admin permissions are split between two principals with different speeds. See
§11 for the full admin surface.

**Temporal Governor (5-day cross-chain proposal cycle) can:**

- Rotate the backend signer
- Whitelist or remove collateral tokens + their Chainlink feeds
- Whitelist or remove principal tokens + their Chainlink feeds (see §7.3)
- Whitelist or remove mTokens
- Change default parameters (grace period, over-seizure bps, etc.) for _new_
  loans
- Set the onchain LTV buffer (`minOriginationLtvBufferBps`)
- Set / rotate the pause guardian
- **Unpause** the factory
- Point the factory at a new `CreditLoan` implementation for _new_ loans

**Pause Guardian (immediate, single-tx) can:**

- Call `pause()` once per incident

**Pause Guardian cannot:**

- Unpause (Temporal Governor only)
- Touch any other admin surface
- Reach into any existing clone

**Neither principal can:**

- Modify any existing loan's terms
- Seize any existing loan's collateral
- Bypass signature verification at match time
- Make existing clones change behavior

---

## 3. Moonwell integration (interfaces you'll call into)

All signatures below are quoted from `moonwell-fi/moonwell-contracts-v2` at SHA
`main` (check the appendix in §17 for fuller snippets).

### 3.1 MToken (Compound v2 fork)

Moonwell uses a `MErc20Delegator` proxy pattern pointing at `MErc20Delegate`
logic. You interact with them as if they were a single contract implementing the
`MTokenInterface` + `MErc20Interface`. The relevant signatures:

```solidity
// ─── Supply / redeem ──────────────────────────────────────────────
function mint(uint mintAmount) external returns (uint);
function redeem(uint redeemTokens) external returns (uint);
function redeemUnderlying(uint redeemAmount) external returns (uint);

// ─── Borrow / repay ───────────────────────────────────────────────
// IMPORTANT: msg.sender-only. No borrowBehalf equivalent exists.
function borrow(uint borrowAmount) external returns (uint);

// Borrower repays their own borrow
function repayBorrow(uint repayAmount) external returns (uint);

// *** The only function that permits a third party to act on another's borrow ***
function repayBorrowBehalf(
  address borrower,
  uint repayAmount
) external returns (uint);

// ─── ERC20 on mToken itself ───────────────────────────────────────
function transfer(address dst, uint256 amount) external returns (bool);
function transferFrom(
  address src,
  address dst,
  uint256 amount
) external returns (bool);
function approve(address spender, uint256 amount) external returns (bool);
function balanceOf(address owner) external view returns (uint256);

// ─── Balance views ────────────────────────────────────────────────
// State-mutating (accrues interest):
function balanceOfUnderlying(address owner) external returns (uint);
function borrowBalanceCurrent(address account) external returns (uint);
function exchangeRateCurrent() external returns (uint);
// Pure views:
function borrowBalanceStored(address account) external view returns (uint);
function exchangeRateStored() external view returns (uint);

// ─── Storage accessors ────────────────────────────────────────────
function underlying() external view returns (address);
function comptroller() external view returns (address);
```

**Why this matters for the marketplace:**

- `borrow()` is msg.sender-only → **the clone must be the Moonwell borrower of
  record** (not the lender, not the factory). That's why we put the mTokens
  inside the clone and have the clone take the borrow.
- `repayBorrowBehalf()` _does_ accept a third party, which we use when a
  lender's rep is paying off a clone's debt during default unwind.
- Function return codes: **0 = success**, nonzero = an error code (Compound v2
  returns error codes _without reverting_). **We must check returns.**

### 3.2 Comptroller

```solidity
// Market membership — required before using an mToken as collateral
function enterMarkets(
  address[] calldata mTokens
) external returns (uint[] memory);
function exitMarket(address mToken) external returns (uint);

// Account state views
function getAccountLiquidity(
  address account
) external view returns (uint, uint, uint);
// Returns: (errorCode, liquidityUsd1e18, shortfallUsd1e18)
function checkMembership(
  address account,
  address mToken
) external view returns (bool);
function getAllMarkets() external view returns (MToken[] memory);

// Caps
function borrowCaps(address mToken) external view returns (uint);
function supplyCaps(address mToken) external view returns (uint);
```

**Usage in the clone:** the clone calls `enterMarkets([mToken])` once at
activation, then `borrow(principal)`. If `getAccountLiquidity` returns
shortfall > 0 at any point, Moonwell can liquidate the clone. That's fine — it's
isolated risk.

### 3.3 Chainlink Oracle (Moonwell's wrapper, for mToken prices)

```solidity
// Moonwell's PriceOracle implementation
contract ChainlinkOracle is PriceOracle {
  /// Returns the price of the underlying token of mToken, scaled to 1e18.
  /// Already normalized for the underlying's decimals.
  function getUnderlyingPrice(MToken mToken) external view returns (uint256);
}
```

**We don't use this oracle for our non-Moonwell collateral.** Moonwell only
registers prices for assets it lists. For collateral like DRB, we register our
own feed (§3.4).

**We do use it:** indirectly, when sanity-checking lender capacity. The lender's
mToken position is valued via `Comptroller.getAccountLiquidity`, which itself
consults `ChainlinkOracle.getUnderlyingPrice`. So we get that for free when we
query the Comptroller.

### 3.4 Chainlink AggregatorV3Interface (for non-Moonwell collateral prices)

```solidity
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer, // <-- the price, in units of `decimals()`
      uint256 startedAt,
      uint256 updatedAt, // <-- unix timestamp, used for staleness check
      uint80 answeredInRound
    );
}
```

**How we use it:**

```solidity
// In CreditLoan, when seizing collateral
AggregatorV3Interface feed = collateralChainlinkFeed;  // immutable, set at init
(, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();

if (answer <= 0) revert InvalidOraclePrice();
if (block.timestamp - updatedAt > stalenessWindow) revert StaleOraclePrice();

// Chainlink USD feeds use 8 decimals typically.
// We want price scaled to 1e18 per unit of collateral (same token decimals).
// Scale up answer by 1e10 to go from 1e8 → 1e18.
uint256 priceScale1e18 = uint256(answer) * 10 ** (18 - feed.decimals());
```

Staleness window is a governance-set parameter on the factory (applied at clone
init — see §6). Typical value: 1 hour for high-activity pairs, 24h for
less-active ones.

### 3.5 Temporal Governor

This is the cross-chain governance executor Moonwell uses on Base and Optimism.
Moonwell governance proposals originate on Moonbeam, are relayed via Wormhole,
and execute on the target chain via the Temporal Governor.

**Addresses (quote these directly when deploying):**

| Chain                  | Chain ID | Temporal Governor                            |
| ---------------------- | -------- | -------------------------------------------- |
| Base mainnet           | 8453     | `0x8b621804a7637b781e2BbD58e256a591F2dF7d51` |
| Optimism mainnet       | 10       | `0x17C9ba3fDa7EC71CcfD75f978Ef31E21927aFF3d` |
| Base Sepolia (testnet) | 84532    | `0xc01EA381A64F8BE3bDBb01A7c34D809f80783662` |

**How other contracts set it as owner:** the common pattern in
`moonwell-contracts-v2` is OpenZeppelin `Ownable` with owner set to the Temporal
Governor at construction. Example usage for the factory:

```solidity
constructor(address _temporalGovernor, /* other args */) Ownable(_temporalGovernor) {
    // ...
}
```

(On OpenZeppelin v5, `Ownable` takes an initial owner in its constructor. On
older versions, `transferOwnership` after deploy.)

---

## 4. Data model

### 4.1 Enums

```solidity
enum OfferStatus {
  Active, // Posted and available to match
  Canceled, // Explicitly canceled by the lender
  Consumed, // Used in a successful match
  Expired // expiresAt passed (lazily marked on query)
}

enum RequestStatus {
  Active,
  Canceled,
  Consumed,
  Expired
}

enum LoanStatus {
  Pending, // Clone deployed but not yet activated (unused in MVP — atomic with deployment)
  Active, // Principal disbursed, repayment expected on schedule
  Settled, // Fully repaid and closed
  Defaulted, // Acceleration triggered; remaining collateral seizable
  Closed // All collateral released and Moonwell debt fully unwound after default
}

enum PaymentKind {
  Interest,
  Principal
}
```

### 4.2 `Offer`

Lives in factory storage.

```solidity
struct Offer {
  address lender; // authored by
  address mToken; // which mToken the lender pledges
  uint256 mTokenAmount; // exact amount of mTokens the lender will deposit
  address principalToken; // what the borrower ultimately wants (usually USDC)
  uint256 maxPrincipal; // lender caps how much can be borrowed against their deposit
  uint16 maxApr; // basis points; backend's apr must be ≤ this
  uint16 minApr; // basis points; backend's apr must be ≥ this
  uint32 minTerm; // seconds; backend's term must be ≥ this
  uint32 maxTerm; // seconds; backend's term must be ≤ this
  address[] acceptedCollateral; // whitelist of collateral tokens the lender will accept
  uint16 minBorrowerCreditTier; // lender's floor on counterparty tier (0 = anyone)
  uint64 expiresAt; // unix seconds; offer is auto-dead after this
  uint256 nonce; // lender-chosen unique value; prevents replay
  OfferStatus status;
}
```

### 4.3 `Request`

Lives in factory storage.

```solidity
struct Request {
  address borrower;
  address principalToken;
  uint256 principal; // exact amount of principal wanted
  address collateralToken;
  uint256 collateralAmount; // exact collateral the borrower will lock
  uint16 maxApr; // borrower caps what they'll pay
  uint32 minTerm;
  uint32 maxTerm;
  uint64 expiresAt;
  uint256 nonce;
  RequestStatus status;
}
```

### 4.4 `PaymentSchedule`

Embedded in `BackendTerms` and copied into the clone at init.

```solidity
struct PaymentSchedule {
  uint32 numInterestPayments; // number of interest-only installments
  uint32 intervalSeconds; // time between interest payments
  uint64 firstInterestDueAt; // unix seconds
  uint64 principalDueAt; // = firstInterestDueAt + numInterestPayments * intervalSeconds
  uint256 interestAmountPerPayment; // exact principalToken amount due each interest payment
  uint256 finalPaymentAmount; // principal + any trailing interest stub
}
```

**Rationale for embedded schedule:** fully self-contained in the clone, no
dependency on factory for schedule-math. Also makes replaying a default
trivially auditable.

### 4.5 `BackendTerms`

The EIP-712 struct the backend signs. Fully describes a loan's economic terms.

```solidity
struct BackendTerms {
  uint256 chainId; // binds terms to a chain
  address factory; // binds terms to a specific factory deployment
  uint256 loanNonce; // unique per loan (used once)
  address lender;
  address borrower;
  address mToken; // from the offer
  uint256 mTokenAmount; // from the offer
  address principalToken; // from the offer / request
  uint256 principal; // from the request
  address collateralToken; // from the request
  uint256 collateralAmount; // from the request
  uint16 apr; // backend-computed; must satisfy offer.minApr ≤ apr ≤ offer.maxApr AND apr ≤ request.maxApr
  uint32 term; // backend-computed; must satisfy offer.minTerm ≤ term ≤ offer.maxTerm, same for request
  PaymentSchedule schedule;
  uint32 gracePeriod; // seconds after a payment due date before clawback can trigger
  uint16 overSeizureBps; // basis points above missed USD that can be seized
  uint16 consecutiveMissesForDefault; // e.g. 2
  uint16 marketplaceFeeBps; // fee on interest
  address feeRecipient;
  uint16 borrowerCreditTier; // from credit bureau at time of match
  uint64 issuedAt;
  uint64 validUntil; // terms are not executable after this
}
```

### 4.6 Per-loan state (lives on the clone)

```solidity
// All written exactly once at initialize(), never updated after:
address public lender;
address public borrower;
address public mToken;
uint256 public mTokenAmount;
address public principalToken;
uint256 public principal;
address public collateralToken;
AggregatorV3Interface public collateralChainlinkFeed;
uint256 public collateralAmount;
uint16 public apr;
uint32 public term;
PaymentSchedule public schedule;
uint32 public gracePeriod;
uint16 public overSeizureBps;
uint16 public consecutiveMissesForDefault;
uint16 public marketplaceFeeBps;
address public feeRecipient;
address public factory;
address public backendSignerAtOrigination;   // snapshot for audit; does not gate any behavior after init
uint64 public activatedAt;
uint32 public stalenessWindow;               // copied from factory at init, frozen from there
address public comptrollerAddr;              // copied for gas efficiency / upgrade independence

// Mutables:
uint32 public paymentCursor;                 // index of the next scheduled interest payment due
uint16 public missedCount;                   // number of missed payments so far
uint256 public totalInterestPaid;
uint256 public totalPrincipalPaid;
uint256 public seizedCollateralAmount;
LoanStatus public status;

// Init guard:
bool private _initialized;
```

---

## 5. EIP-712 signatures

Three distinct typed data schemes. All share a single domain separator per
factory deployment.

### 5.1 Domain separator

```solidity
bytes32 public constant EIP712_DOMAIN_TYPEHASH = keccak256(
    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
);

bytes32 public immutable DOMAIN_SEPARATOR;

constructor(...) {
    DOMAIN_SEPARATOR = keccak256(
        abi.encode(
            EIP712_DOMAIN_TYPEHASH,
            keccak256(bytes("MoonwellCreditMarketplace")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        )
    );
}
```

Name: `"MoonwellCreditMarketplace"`. Version: `"1"`. `chainId` and
`verifyingContract` are self-explanatory.

### 5.2 `OFFER_TYPEHASH` (lender signs)

```solidity
bytes32 public constant OFFER_TYPEHASH = keccak256(
    "Offer("
        "address lender,"
        "address mToken,"
        "uint256 mTokenAmount,"
        "address principalToken,"
        "uint256 maxPrincipal,"
        "uint16 maxApr,"
        "uint16 minApr,"
        "uint32 minTerm,"
        "uint32 maxTerm,"
        "bytes32 acceptedCollateralHash,"
        "uint16 minBorrowerCreditTier,"
        "uint64 expiresAt,"
        "uint256 nonce"
    ")"
);
```

**Note:** `acceptedCollateral` is variable-length so we hash the packed list
into
`bytes32 acceptedCollateralHash = keccak256(abi.encodePacked(acceptedCollateral))`
and include the hash in the typed data. This is the standard EIP-712 treatment
of dynamic arrays.

Struct hash computation:

```solidity
function _hashOffer(Offer memory o) internal pure returns (bytes32) {
  return
    keccak256(
      abi.encode(
        OFFER_TYPEHASH,
        o.lender,
        o.mToken,
        o.mTokenAmount,
        o.principalToken,
        o.maxPrincipal,
        o.maxApr,
        o.minApr,
        o.minTerm,
        o.maxTerm,
        keccak256(abi.encodePacked(o.acceptedCollateral)),
        o.minBorrowerCreditTier,
        o.expiresAt,
        o.nonce
      )
    );
}
```

Full digest for signing:

```solidity
bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, _hashOffer(offer)));
```

Verification via OpenZeppelin's `ECDSA.recover(digest, signature)` must equal
`offer.lender`.

### 5.3 `REQUEST_TYPEHASH` (borrower signs)

```solidity
bytes32 public constant REQUEST_TYPEHASH = keccak256(
    "Request("
        "address borrower,"
        "address principalToken,"
        "uint256 principal,"
        "address collateralToken,"
        "uint256 collateralAmount,"
        "uint16 maxApr,"
        "uint32 minTerm,"
        "uint32 maxTerm,"
        "uint64 expiresAt,"
        "uint256 nonce"
    ")"
);
```

Standard struct hash (no dynamic fields). Recover must equal `request.borrower`.

### 5.4 `PAYMENT_SCHEDULE_TYPEHASH` and `BACKEND_TERMS_TYPEHASH`

```solidity
bytes32 public constant PAYMENT_SCHEDULE_TYPEHASH = keccak256(
    "PaymentSchedule("
        "uint32 numInterestPayments,"
        "uint32 intervalSeconds,"
        "uint64 firstInterestDueAt,"
        "uint64 principalDueAt,"
        "uint256 interestAmountPerPayment,"
        "uint256 finalPaymentAmount"
    ")"
);

bytes32 public constant BACKEND_TERMS_TYPEHASH = keccak256(
    "BackendTerms("
        "uint256 chainId,"
        "address factory,"
        "uint256 loanNonce,"
        "address lender,"
        "address borrower,"
        "address mToken,"
        "uint256 mTokenAmount,"
        "address principalToken,"
        "uint256 principal,"
        "address collateralToken,"
        "uint256 collateralAmount,"
        "uint16 apr,"
        "uint32 term,"
        "PaymentSchedule schedule,"
        "uint32 gracePeriod,"
        "uint16 overSeizureBps,"
        "uint16 consecutiveMissesForDefault,"
        "uint16 marketplaceFeeBps,"
        "address feeRecipient,"
        "uint16 borrowerCreditTier,"
        "uint64 issuedAt,"
        "uint64 validUntil"
    ")"
    "PaymentSchedule("
        "uint32 numInterestPayments,"
        "uint32 intervalSeconds,"
        "uint64 firstInterestDueAt,"
        "uint64 principalDueAt,"
        "uint256 interestAmountPerPayment,"
        "uint256 finalPaymentAmount"
    ")"
);
```

**Important:** EIP-712 nested struct encoding requires the referenced type's
definition to be concatenated _after_ the main type definition, sorted
alphabetically. Since `BackendTerms` references `PaymentSchedule`, the full
string is `BackendTerms(...)PaymentSchedule(...)`.

Struct hash of `BackendTerms` substitutes
`keccak256(_hashPaymentSchedule(schedule))` for the `schedule` field:

```solidity
function _hashPaymentSchedule(
  PaymentSchedule memory s
) internal pure returns (bytes32) {
  return
    keccak256(
      abi.encode(
        PAYMENT_SCHEDULE_TYPEHASH,
        s.numInterestPayments,
        s.intervalSeconds,
        s.firstInterestDueAt,
        s.principalDueAt,
        s.interestAmountPerPayment,
        s.finalPaymentAmount
      )
    );
}

function _hashBackendTerms(
  BackendTerms memory t
) internal pure returns (bytes32) {
  return
    keccak256(
      abi.encode(
        BACKEND_TERMS_TYPEHASH,
        t.chainId,
        t.factory,
        t.loanNonce,
        t.lender,
        t.borrower,
        t.mToken,
        t.mTokenAmount,
        t.principalToken,
        t.principal,
        t.collateralToken,
        t.collateralAmount,
        t.apr,
        t.term,
        _hashPaymentSchedule(t.schedule),
        t.gracePeriod,
        t.overSeizureBps,
        t.consecutiveMissesForDefault,
        t.marketplaceFeeBps,
        t.feeRecipient,
        t.borrowerCreditTier,
        t.issuedAt,
        t.validUntil
      )
    );
}
```

Recover must equal the factory's current `backendSigner`.

### 5.5 `OFFER_CANCEL_TYPEHASH` and `REQUEST_CANCEL_TYPEHASH` (cancel intents)

Cancel signatures must be **EIP-712 typed data bound to the factory's domain
separator** — same envelope as every other signed payload — otherwise a signed
cancel from a stale/test deployment is replayable against production. They also
bind to the `nonce` being burned so the signature's authority is scoped to
invalidating exactly that nonce.

```solidity
bytes32 public constant OFFER_CANCEL_TYPEHASH = keccak256(
    "OfferCancel(uint256 offerId,address lender,uint256 nonce)"
);

bytes32 public constant REQUEST_CANCEL_TYPEHASH = keccak256(
    "RequestCancel(uint256 requestId,address borrower,uint256 nonce)"
);

function _hashOfferCancel(
    uint256 offerId,
    address lender,
    uint256 nonce
) internal pure returns (bytes32) {
    return keccak256(
        abi.encode(OFFER_CANCEL_TYPEHASH, offerId, lender, nonce)
    );
}

function _hashRequestCancel(
    uint256 requestId,
    address borrower,
    uint256 nonce
) internal pure returns (bytes32) {
    return keccak256(
        abi.encode(REQUEST_CANCEL_TYPEHASH, requestId, borrower, nonce)
    );
}
```

Full digest for signing (identical envelope to §5.2):

```solidity
bytes32 digest = keccak256(
    abi.encodePacked(
        "\x19\x01",
        DOMAIN_SEPARATOR,
        _hashOfferCancel(offerId, lender, nonce)
    )
);
```

Verification via `ECDSA.recover(digest, signature)` must equal the offer's
`lender` (resp. the request's `borrower`). See §7.2 for the full cancel flow.

### 5.6 Replay prevention

Each signer owns their own nonce namespace:

```solidity
// factory storage
mapping(address => mapping(uint256 => bool)) public usedNonces;
    // usedNonces[signer][nonce] = true once consumed

function _consumeNonce(address signer, uint256 nonce) internal {
    if (usedNonces[signer][nonce]) revert NonceAlreadyUsed();
    usedNonces[signer][nonce] = true;
}
```

At match time, the factory consumes:

- `offer.lender`'s nonce = `offer.nonce`
- `request.borrower`'s nonce = `request.nonce`
- `backendSigner`'s nonce = `backendTerms.loanNonce`

Offers and requests can be canceled before consumption via `cancelOffer` /
`cancelRequest`, which also burn the nonce.

### 5.7 Signature format

All signatures are 65 bytes (EIP-2098 compact sigs are fine to accept —
OpenZeppelin's ECDSA handles both). `ecrecover`-compatible. Smart-account
signers (EIP-1271) are **out of scope for MVP** — only EOAs (the lender and
borrower must be EOAs, and the backend must be an EOA). Supporting EIP-1271 is a
phase-2 enhancement.

---

## 6. Storage layout

### 6.1 Factory storage (`CreditMarketplaceFactory`)

```solidity
// ─── EIP-712 ─────────────────────────────────────────────────────
bytes32 public immutable DOMAIN_SEPARATOR;

// ─── Ownership (OpenZeppelin Ownable inheritance) ────────────────

// ─── Backend signer ──────────────────────────────────────────────
address public backendSigner;

// ─── Pause guardian (separate from owner / Temporal Governor) ────
// Can call pause() but NOT unpause(). Rotated only by owner via setPauseGuardian.
address public pauseGuardian;

// ─── Collateral whitelist ────────────────────────────────────────
mapping(address => AggregatorV3Interface) public collateralFeeds;  // token → Chainlink feed
mapping(address => bool) public isCollateralWhitelisted;

// ─── Principal-token whitelist (for onchain LTV check at match) ──
// Every principal token offered must have a registered Chainlink feed so
// createLoan can price it in USD at origination (see §7.3).
mapping(address => AggregatorV3Interface) public principalTokenFeeds;
mapping(address => bool) public isPrincipalTokenWhitelisted;

// ─── Onchain LTV buffer (basis points above 100%) ────────────────
// collateralValueUsd1e18 must be ≥ principalValueUsd1e18 * (10_000 + buffer) / 10_000
// at match time. E.g. 1_000 bps = 10% — collateral must be worth at least 110%
// of principal in USD at the moment createLoan executes.
uint16 public minOriginationLtvBufferBps;

// ─── mToken whitelist ────────────────────────────────────────────
mapping(address => bool) public isMTokenWhitelisted;

// ─── Default parameters (copied into clone at init) ──────────────
uint32 public defaultGracePeriod;            // e.g. 86400 (24h)
uint16 public defaultOverSeizureBps;         // e.g. 2000 (20%)
uint16 public defaultConsecutiveMissesForDefault;  // e.g. 2
uint16 public defaultMarketplaceFeeBps;      // e.g. 500 (5%)
address public feeRecipient;
uint32 public stalenessWindow;               // e.g. 3600 (1h)

// ─── Implementation pointer ──────────────────────────────────────
address public creditLoanImplementation;     // updated by governance for new loans

// ─── External anchors ────────────────────────────────────────────
address public immutable comptroller;
address public immutable temporalGovernor;   // stored for clarity; also = owner()

// ─── Order book ──────────────────────────────────────────────────
mapping(uint256 => Offer) public offers;
mapping(uint256 => Request) public requests;
uint256 public nextOfferId;
uint256 public nextRequestId;

// ─── Deployed loans registry ─────────────────────────────────────
mapping(uint256 => address) public loans;    // loanId → clone address
uint256 public nextLoanId;

// ─── Replay protection ───────────────────────────────────────────
mapping(address => mapping(uint256 => bool)) public usedNonces;

// ─── Pause ───────────────────────────────────────────────────────
// (via OZ Pausable inheritance)
```

### 6.2 Clone storage (`CreditLoan` implementation)

See §4.6.

### 6.3 Implementation-contract lock

The `CreditLoan` implementation itself must not be initializable, to prevent
someone from calling `initialize` on the impl address and hijacking its storage
slots (which would be read by calls to the impl but do not affect clones).

```solidity
// In the factory constructor, immediately after deploying or accepting the impl:
InitParams memory sentinel;                             // all fields default to 0
CreditLoan(creditLoanImplementation).initialize(sentinel);
// After this, `_initialized == true` on the impl, so it can never be re-initialized.
// `factory` is bound to `msg.sender` (the factory contract) inside initialize;
// see §12.6 for the trust model.
```

This is identical to the technique OZ `Initializable` uses for UUPS proxies. We
just use a plain guard because we're not using OZ `Initializable` (no
upgradability for clones).

---

## 7. Core flows

### 7.1 Post offer

```
Caller: anyone (gas payer)
Inputs: Offer offer, bytes signature

Factory.postOffer(offer, signature):
  require !paused
  require offer.expiresAt > block.timestamp
  require offer.maxApr >= offer.minApr
  require offer.maxTerm >= offer.minTerm
  require offer.mToken whitelisted
  require offer.principalToken whitelisted  // must have a principalTokenFeeds entry (see §7.3)
  require each token in offer.acceptedCollateral is whitelisted
  digest = hashOffer(offer) → EIP-712
  recovered = ECDSA.recover(digest, signature)
  require recovered == offer.lender
  require !usedNonces[offer.lender][offer.nonce]

  offerId = nextOfferId++
  offers[offerId] = offer with status=Active
  // Note: nonce is NOT consumed at post — only at successful match or at cancel.
  // This allows the same offer to be re-posted (different offerId) if canceled.

  emit OfferPosted(offerId, offer.lender, offer.mToken, offer.mTokenAmount, ...)
```

### 7.2 Cancel offer / cancel request

Both cancel flows use the EIP-712 typehashes defined in §5.5 and the same
`"\x19\x01" || DOMAIN_SEPARATOR || structHash` envelope as every other signed
payload. This binds the cancel signature to the chainId + factory address + the
specific nonce being burned.

```
Caller: anyone (gas payer) — the cancelSignature is what proves authority
Inputs: uint256 offerId, bytes cancelSignature

Factory.cancelOffer(offerId, cancelSignature):
  Offer storage o = offers[offerId]
  require o.status == Active
  require !usedNonces[o.lender][o.nonce]  // defensive — should already be false

  bytes32 structHash = _hashOfferCancel(offerId, o.lender, o.nonce)
  bytes32 digest     = keccak256(
      abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
  )
  address recovered  = ECDSA.recover(digest, cancelSignature)
  require recovered == o.lender

  usedNonces[o.lender][o.nonce] = true  // burn the nonce
  o.status = OfferStatus.Canceled
  emit OfferCanceled(offerId)
```

```
Caller: anyone (gas payer)
Inputs: uint256 requestId, bytes cancelSignature

Factory.cancelRequest(requestId, cancelSignature):
  Request storage r = requests[requestId]
  require r.status == Active
  require !usedNonces[r.borrower][r.nonce]

  bytes32 structHash = _hashRequestCancel(requestId, r.borrower, r.nonce)
  bytes32 digest     = keccak256(
      abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
  )
  address recovered  = ECDSA.recover(digest, cancelSignature)
  require recovered == r.borrower

  usedNonces[r.borrower][r.nonce] = true
  r.status = RequestStatus.Canceled
  emit RequestCanceled(requestId)
```

### 7.3 Match flow — `createLoan`

This is the heart of the contract. All three signatures verified, clone
deployed, funds moved atomically.

```
Caller: backend (msg.sender = address holding backend key) — but in principle anyone can submit if they hold valid signatures
Inputs:
  uint256 offerId,
  uint256 requestId,
  BackendTerms terms,
  bytes offerSig,
  bytes requestSig,
  bytes backendSig

Factory.createLoan(offerId, requestId, terms, offerSig, requestSig, backendSig):
  require !paused

  // ─── Load + validate stored offer/request ───
  Offer storage o = offers[offerId]
  Request storage r = requests[requestId]
  require o.status == Active
  require r.status == Active
  require o.expiresAt > block.timestamp
  require r.expiresAt > block.timestamp

  // ─── Verify signatures ───
  bytes32 offerDigest = EIP712.hash(DOMAIN_SEPARATOR, hashOffer(o))
  require ECDSA.recover(offerDigest, offerSig) == o.lender

  bytes32 requestDigest = EIP712.hash(DOMAIN_SEPARATOR, hashRequest(r))
  require ECDSA.recover(requestDigest, requestSig) == r.borrower

  bytes32 termsDigest = EIP712.hash(DOMAIN_SEPARATOR, hashBackendTerms(terms))
  require ECDSA.recover(termsDigest, backendSig) == backendSigner

  // ─── Freshness + scope ───
  require terms.validUntil > block.timestamp
  require terms.chainId == block.chainid
  require terms.factory == address(this)

  // ─── Nonce consumption ───
  require !usedNonces[o.lender][o.nonce]
  require !usedNonces[r.borrower][r.nonce]
  require !usedNonces[backendSigner][terms.loanNonce]
  usedNonces[o.lender][o.nonce] = true
  usedNonces[r.borrower][r.nonce] = true
  usedNonces[backendSigner][terms.loanNonce] = true

  // ─── Bounds checks: terms must fit inside offer and request bounds ───
  require terms.lender == o.lender
  require terms.borrower == r.borrower
  require terms.mToken == o.mToken
  require terms.mTokenAmount == o.mTokenAmount
  require terms.principalToken == o.principalToken
  require terms.principalToken == r.principalToken
  require terms.principal <= o.maxPrincipal
  require terms.principal == r.principal
  require terms.collateralToken == r.collateralToken
  require terms.collateralAmount == r.collateralAmount
  require terms.apr >= o.minApr && terms.apr <= o.maxApr
  require terms.apr <= r.maxApr
  require terms.term >= o.minTerm && terms.term <= o.maxTerm
  require terms.term >= r.minTerm && terms.term <= r.maxTerm
  require _containsCollateral(o.acceptedCollateral, r.collateralToken)
  require terms.borrowerCreditTier >= o.minBorrowerCreditTier

  // ─── Sanity check: lender's Moonwell position supports this pledge ───
  // Not strictly required (clone isolates risk), but catches bad offers cheaply.
  require IERC20(o.mToken).balanceOf(o.lender) >= o.mTokenAmount

  // ─── Onchain overcollateralization check (Chainlink at match time) ───
  // This is the on-chain enforcement that the loan is overcollateralized at
  // origination. Backend pricing is advisory — governance-curated feeds are
  // authoritative. A compromised backend key cannot originate an under-water
  // loan because both sides are re-priced here from the Chainlink feeds.
  AggregatorV3Interface principalFeed  = principalTokenFeeds[o.principalToken]
  AggregatorV3Interface collateralFeed = collateralFeeds[r.collateralToken]
  require address(principalFeed)  != address(0)   // NotPrincipalTokenWhitelisted
  require address(collateralFeed) != address(0)   // NotCollateralWhitelisted

  uint256 collateralUsd1e18 = _valueToUsd1e18(
      r.collateralToken,
      r.collateralAmount,
      collateralFeed,
      stalenessWindow
  )
  uint256 principalUsd1e18  = _valueToUsd1e18(
      o.principalToken,
      terms.principal,
      principalFeed,
      stalenessWindow
  )
  uint256 requiredUsd1e18 = principalUsd1e18 * (10_000 + minOriginationLtvBufferBps) / 10_000
  if (collateralUsd1e18 < requiredUsd1e18)
    revert InsufficientCollateral(collateralUsd1e18, requiredUsd1e18)

  // `_valueToUsd1e18` is a shared internal helper (see below) that reverts on
  // `answer <= 0` (InvalidOraclePrice) and on staleness
  // (`block.timestamp - updatedAt > maxAge` → StaleOraclePrice). It normalizes
  // to 1e18 using the token's and the feed's reported decimals.

  // ─── Deploy + initialize clone ───
  address loanAddr = Clones.clone(creditLoanImplementation)

  // Snapshot governance params at init
  CreditLoan(loanAddr).initialize({
    lender: o.lender,
    borrower: r.borrower,
    mToken: o.mToken,
    mTokenAmount: o.mTokenAmount,
    principalToken: o.principalToken,
    principal: terms.principal,
    collateralToken: r.collateralToken,
    collateralChainlinkFeed: collateralFeeds[r.collateralToken],
    collateralAmount: r.collateralAmount,
    apr: terms.apr,
    term: terms.term,
    schedule: terms.schedule,
    gracePeriod: terms.gracePeriod,
    overSeizureBps: terms.overSeizureBps,
    consecutiveMissesForDefault: terms.consecutiveMissesForDefault,
    marketplaceFeeBps: terms.marketplaceFeeBps,
    feeRecipient: terms.feeRecipient,
    backendSignerAtOrigination: backendSigner,
    stalenessWindow: stalenessWindow,
    comptrollerAddr: comptroller
    // `factory` is NOT passed in InitParams — it is bound inside
    // initialize() as `msg.sender`, which is this factory contract during
    // this call. Prevents anyone from impersonating the factory by
    // pre-initializing a freshly-cloned CreditLoan out-of-band (§12.6).
  })

  // ─── Move funds ───
  // Lender's mTokens → clone. Requires lender.approve(factory, mTokenAmount).
  IERC20(o.mToken).safeTransferFrom(o.lender, loanAddr, o.mTokenAmount)

  // Borrower's collateral → clone. Requires borrower.approve(factory, collateralAmount).
  IERC20(r.collateralToken).safeTransferFrom(r.borrower, loanAddr, r.collateralAmount)

  // ─── Activate loan ───
  CreditLoan(loanAddr).activate()
  // activate() does internally:
  //   - comptroller.enterMarkets([mToken]) as msg.sender = clone
  //   - mToken.borrow(principal) as msg.sender = clone → clone receives principalToken
  //   - IERC20(principalToken).safeTransfer(borrower, principal)
  //   - status = Active; activatedAt = block.timestamp

  // ─── Bookkeeping ───
  o.status = OfferStatus.Consumed
  r.status = RequestStatus.Consumed
  uint256 loanId = nextLoanId++
  loans[loanId] = loanAddr

  emit LoanCreated(loanId, loanAddr, o.lender, r.borrower, terms.principal, terms.apr, terms.term)
```

**Shared USD-pricing helper (used by §7.3 and §7.5):**

```solidity
function _valueToUsd1e18(
  address token,
  uint256 amount,
  AggregatorV3Interface feed,
  uint32 maxAge
) internal view returns (uint256) {
  (, int256 answer, , uint256 updatedAt, ) = feed.latestRoundData();
  if (answer <= 0) revert InvalidOraclePrice();
  if (block.timestamp - updatedAt > maxAge) revert StaleOraclePrice();

  uint256 feedDecimals = feed.decimals(); // typically 8
  uint256 tokenDecimals = IERC20Metadata(token).decimals();

  // price per 1 token, scaled to 1e18
  uint256 pricePerTokenUsd1e18 = uint256(answer) * (10 ** (18 - feedDecimals));

  // value = amount * pricePerToken / 10^tokenDecimals, scaled to 1e18
  return (amount * pricePerTokenUsd1e18) / (10 ** tokenDecimals);
}
```

Reused by `claimMissedPayment` (§7.5) so the staleness + non-positive-answer
guards and the decimal normalization live in exactly one place.

### 7.4 Make payment

```
Caller: borrower (enforced by require)
Context: called directly on the clone (not the factory)

CreditLoan.makePayment():
  require status == Active
  require msg.sender == borrower

  uint32 cursor = paymentCursor
  uint256 amountDue
  PaymentKind kind

  if cursor < schedule.numInterestPayments:
    amountDue = schedule.interestAmountPerPayment
    kind = Interest
    require block.timestamp < _interestDueAt(cursor) + gracePeriod  // not too late
  else:
    // This is the final principal payment
    amountDue = schedule.finalPaymentAmount
    kind = Principal
    require block.timestamp < schedule.principalDueAt + gracePeriod

  IERC20(principalToken).safeTransferFrom(borrower, address(this), amountDue)

  if kind == Interest:
    totalInterestPaid += amountDue
    paymentCursor = cursor + 1
    missedCount = 0  // reset on successful payment
    emit InterestPaid(cursor, amountDue)
  else:
    totalPrincipalPaid += amountDue
    paymentCursor = cursor + 1
    _settle()  // internal: repays Moonwell, returns mTokens to lender, returns residual collateral, distributes fee
    // status = Settled at end of _settle
    emit LoanSettled()
```

Interest is paid in the **principalToken** (USDC), not the collateralToken.
Simplifies math.

### 7.5 Claim missed payment (progressive clawback)

```
Caller: anyone (typically lender; keeper bots could do it too)

CreditLoan.claimMissedPayment():
  require status == Active

  uint32 cursor = paymentCursor
  require cursor <= schedule.numInterestPayments  // not past final principal yet (use accelerate/settle instead)

  uint64 dueAt = _interestDueAt(cursor)
  require block.timestamp > dueAt + gracePeriod  // past grace

  uint256 missedAmountUsd = schedule.interestAmountPerPayment
  // (we denominate in principalToken, which is USDC-like — so "USD" and "USDC 1e6" differ.
  //  For the oracle math, treat principalToken as 1 USD at its own decimals; Chainlink output
  //  gives us collateral USD price; compute seize in collateral-token units.)

  (, int256 answer, , uint256 updatedAt, ) = collateralChainlinkFeed.latestRoundData()
  if answer <= 0 revert InvalidOraclePrice()
  if block.timestamp - updatedAt > stalenessWindow revert StaleOraclePrice()

  // Normalize both sides to 1e18 USD
  uint256 collateralPriceUsd1e18 = uint256(answer) * 10 ** (18 - collateralChainlinkFeed.decimals())
  uint256 principalDecimals = IERC20Metadata(principalToken).decimals()
  uint256 missedUsd1e18 = (missedAmountUsd * 1e18) / (10 ** principalDecimals)
  uint256 seizeUsd1e18 = (missedUsd1e18 * (10_000 + overSeizureBps)) / 10_000
  uint256 collateralDecimals = IERC20Metadata(collateralToken).decimals()
  uint256 seizeCollateralAmount = (seizeUsd1e18 * 10 ** collateralDecimals) / collateralPriceUsd1e18

  uint256 available = collateralAmount - seizedCollateralAmount
  if seizeCollateralAmount > available seizeCollateralAmount = available  // cap

  seizedCollateralAmount += seizeCollateralAmount
  missedCount += 1
  paymentCursor = cursor + 1  // move past the missed payment — lender is compensated via seize

  IERC20(collateralToken).safeTransfer(lender, seizeCollateralAmount)
  emit CollateralSeized(cursor, missedAmountUsd, seizeCollateralAmount)

  if missedCount >= consecutiveMissesForDefault:
    _accelerate()
```

**On cap hitting `available`:** if the remaining collateral can't cover the
missed payment + over-seizure, the loan goes into default regardless of
`consecutiveMissesForDefault`. The lender takes what's left; the rest is a
deficiency (documented limitation — MVP does not try to recoup from elsewhere).

### 7.6 Accelerate (default)

```
Internal, triggered by missedCount ≥ consecutiveMissesForDefault or by principal-due + grace expiry

CreditLoan._accelerate():
  status = Defaulted
  emit LoanDefaulted(missedCount, block.timestamp)
```

After acceleration, the lender can call `seizeAll()` to take all remaining
collateral without per-payment oracle math. This skips the per-payment seize
calculation — the lender is now claiming full remaining value.

```
Caller: lender

CreditLoan.seizeAll():
  require status == Defaulted
  require msg.sender == lender
  uint256 remaining = collateralAmount - seizedCollateralAmount
  seizedCollateralAmount = collateralAmount
  status = Closed
  IERC20(collateralToken).safeTransfer(lender, remaining)
  emit DefaultSeized(remaining)
  // Note: the Moonwell borrow on this clone remains open. The lender is responsible
  // for unwinding off-contract: convert seized collateral to principalToken via a DEX,
  // then call repayBorrowBehalf on the clone to close its Moonwell position, then
  // call redeemAndReturn() to retrieve the mTokens.
```

Optional helper (keep or defer):

```
CreditLoan.repayLoanAfterDefault(uint256 repayAmount):
  require status == Closed
  IERC20(principalToken).safeTransferFrom(msg.sender, address(this), repayAmount)
  IERC20(principalToken).forceApprove(mToken, repayAmount)  // OZ ≥ 4.9 — tolerates non-zero prior allowance
  MToken(mToken).repayBorrowBehalf(address(this), repayAmount)

CreditLoan.redeemAndReturn():
  require status == Closed
  require MToken(mToken).borrowBalanceStored(address(this)) == 0
  uint256 mBal = IERC20(mToken).balanceOf(address(this))
  IERC20(mToken).safeTransfer(lender, mBal)
  emit LenderReimbursed(mBal)
```

### 7.7 Settle (happy path)

```
Internal, called at end of final principal payment

CreditLoan._settle():
  // 1. Repay Moonwell using accumulated principalToken in this contract.
  //    We pass `type(uint).max` as the repay amount — Moonwell's MToken
  //    (Compound v2 fork, see src/MToken.sol:1297) interprets that sentinel
  //    as "repay the full outstanding borrow", so we don't have to match the
  //    exact `borrowBalanceCurrent` value and can't overshoot. We also
  //    forceApprove(type(uint).max) so any residual allowance from a prior
  //    repay-then-revert sequence is overwritten cleanly.
  //
  //    We still read `borrowBalanceCurrent` first to pre-flight the solvency
  //    check: if the clone doesn't hold enough principalToken to cover
  //    Moonwell's current borrow balance (because Moonwell's borrow APR
  //    outpaced the marketplace APR baked into finalPaymentAmount), we
  //    revert with a specific error so the lender can route to the default
  //    unwind path (§7.6) instead of a silent SafeERC20 revert.
  uint256 borrowBal = MToken(mToken).borrowBalanceCurrent(address(this))
  uint256 selfBal   = IERC20(principalToken).balanceOf(address(this))
  if (selfBal < borrowBal)
    revert InsufficientPrincipalForRepay(selfBal, borrowBal)
  IERC20(principalToken).forceApprove(mToken, type(uint).max)
  uint err = MToken(mToken).repayBorrowBehalf(address(this), type(uint).max)
  require err == 0

  // 2. Compute interest fee split
  //    totalInterestPaid is what came in; fee is marketplaceFeeBps of it
  uint256 fee = (totalInterestPaid * marketplaceFeeBps) / 10_000
  uint256 lenderInterest = totalInterestPaid - fee

  // 3. Pay out
  if fee > 0:
    IERC20(principalToken).safeTransfer(feeRecipient, fee)
  if lenderInterest > 0:
    IERC20(principalToken).safeTransfer(lender, lenderInterest)

  // 4. Return lender's mTokens (they accrued Moonwell supply yield during loan)
  uint256 mBal = IERC20(mToken).balanceOf(address(this))
  IERC20(mToken).safeTransfer(lender, mBal)

  // 5. Return borrower's unseized collateral
  uint256 remainingCol = collateralAmount - seizedCollateralAmount
  if remainingCol > 0:
    IERC20(collateralToken).safeTransfer(borrower, remainingCol)

  status = Settled
  emit LoanSettled()
```

**Solvency note (APR floor).** `_settle` requires the clone to hold at least
`borrowBalanceCurrent(this)` of `principalToken` at the moment of settlement. If
Moonwell's borrow APR exceeds the marketplace APR baked into
`finalPaymentAmount` over the term, the clone is short by the delta and
`_settle` reverts with `InsufficientPrincipalForRepay`. The marketplace APR
floor MUST be priced above the prevailing Moonwell borrow rate plus a buffer;
the backend pricing engine is responsible for enforcing this at match time (this
is not checked on-chain at `createLoan` — see §16). If `_settle` does revert,
the lender unwinds via the default path (§7.6): convert collateral they already
hold (or solicited via keeper) to `principalToken`, call `repayLoanAfterDefault`
to zero the Moonwell borrow, then `redeemAndReturn` to reclaim mTokens. The loan
is not lost, just stuck until the shortfall is covered.

### 7.8 Scheduled-payment-due-date helper

```solidity
function _interestDueAt(uint32 cursor) internal view returns (uint64) {
  // cursor is zero-indexed
  return
    schedule.firstInterestDueAt +
    uint64(cursor) *
    uint64(schedule.intervalSeconds);
}
```

---

## 8. External interfaces (full signatures)

### 8.1 `CreditMarketplaceFactory`

```solidity
interface ICreditMarketplaceFactory {
  // ─── Posting ───
  function postOffer(
    Offer calldata offer,
    bytes calldata signature
  ) external returns (uint256 offerId);
  function postRequest(
    Request calldata request,
    bytes calldata signature
  ) external returns (uint256 requestId);
  function cancelOffer(
    uint256 offerId,
    bytes calldata cancelSignature
  ) external;
  function cancelRequest(
    uint256 requestId,
    bytes calldata cancelSignature
  ) external;

  // ─── Matching ───
  function createLoan(
    uint256 offerId,
    uint256 requestId,
    BackendTerms calldata terms,
    bytes calldata offerSig,
    bytes calldata requestSig,
    bytes calldata backendSig
  ) external returns (uint256 loanId, address loanAddress);

  // ─── Views ───
  function getOffer(uint256 offerId) external view returns (Offer memory);
  function getRequest(uint256 requestId) external view returns (Request memory);
  function getLoan(uint256 loanId) external view returns (address);
  function isNonceUsed(
    address signer,
    uint256 nonce
  ) external view returns (bool);

  // ─── Admin (onlyOwner = Temporal Governor) ───
  function setBackendSigner(address newSigner) external;
  function setCreditLoanImplementation(address newImpl) external;
  function whitelistMToken(address mToken, bool allowed) external;
  function whitelistCollateralToken(
    address token,
    AggregatorV3Interface feed
  ) external;
  function removeCollateralToken(address token) external;
  function whitelistPrincipalToken(
    address token,
    AggregatorV3Interface feed
  ) external;
  function removePrincipalToken(address token) external;
  function setStalenessWindow(uint32 seconds_) external;
  function setMinOriginationLtvBufferBps(uint16 bufferBps) external;
  function setDefaultParams(
    uint32 gracePeriod,
    uint16 overSeizureBps,
    uint16 consecutiveMissesForDefault,
    uint16 marketplaceFeeBps
  ) external;
  function setFeeRecipient(address recipient) external;
  function setPauseGuardian(address newGuardian) external; // onlyOwner
  function unpause() external; // onlyOwner

  // ─── Pause (onlyOwner or pauseGuardian) ───
  function pause() external;
}
```

### 8.2 `ICreditLoan`

```solidity
interface ICreditLoan {
  // ─── Lifecycle (only callable by factory during createLoan) ───
  function initialize(InitParams calldata params) external;
  function activate() external;

  // ─── Borrower actions ───
  function makePayment() external;

  // ─── Anyone can call ───
  function claimMissedPayment() external;

  // ─── Post-default (lender-only) ───
  function seizeAll() external;
  function repayLoanAfterDefault(uint256 repayAmount) external;
  function redeemAndReturn() external;

  // ─── Views ───
  function status() external view returns (LoanStatus);
  function nextPaymentDueAt() external view returns (uint64);
  function remainingPayments() external view returns (uint32);
  function totalOwedNow()
    external
    view
    returns (uint256 principal, uint256 interest);
  function collateralRemaining() external view returns (uint256);
}
```

`InitParams` is a struct of every immutable field — too big to pass individually
without blowing the stack.

### 8.3 `CreditLoan` constructor

`CreditLoan` has no constructor (clones never run constructors — they only
delegatecall to logic). All one-time setup happens in `initialize`.

The implementation contract itself is deployed once and has its `_initialized`
flipped to `true` by the factory constructor (see §6.3) so no one can call
`initialize` on the impl directly.

---

## 9. Events

For lunar-indexer and the frontend. Every structural event should be indexed on
the most useful dimensions.

### 9.1 Factory events

```solidity
event OfferPosted(
  uint256 indexed offerId,
  address indexed lender,
  address indexed mToken,
  uint256 mTokenAmount,
  address principalToken,
  uint256 maxPrincipal,
  uint16 maxApr,
  uint64 expiresAt
);
event OfferCanceled(uint256 indexed offerId);

event RequestPosted(
  uint256 indexed requestId,
  address indexed borrower,
  address principalToken,
  uint256 principal,
  address indexed collateralToken,
  uint256 collateralAmount,
  uint16 maxApr,
  uint64 expiresAt
);
event RequestCanceled(uint256 indexed requestId);

event LoanCreated(
  uint256 indexed loanId,
  address indexed loanAddress,
  address indexed lender,
  address borrower,
  uint256 principal,
  uint16 apr,
  uint32 term
);

event BackendSignerUpdated(
  address indexed previousSigner,
  address indexed newSigner
);
event CollateralWhitelisted(address indexed token, address indexed feed);
event CollateralRemoved(address indexed token);
event PrincipalTokenWhitelisted(address indexed token, address indexed feed);
event PrincipalTokenRemoved(address indexed token);
event MTokenWhitelisted(address indexed mToken, bool allowed);
event DefaultParamsUpdated(
  uint32 gracePeriod,
  uint16 overSeizureBps,
  uint16 consecutiveMissesForDefault,
  uint16 marketplaceFeeBps
);
event StalenessWindowUpdated(uint32 seconds_);
event MinOriginationLtvBufferBpsUpdated(uint16 previous, uint16 updated);
event FeeRecipientUpdated(address indexed previous, address indexed updated);
event CreditLoanImplementationUpdated(
  address indexed previous,
  address indexed updated
);
event PauseGuardianUpdated(
  address indexed previousGuardian,
  address indexed newGuardian
);
// (Pausable's built-in Paused(address) / Unpaused(address) are inherited.)
```

### 9.2 CreditLoan events

```solidity
event LoanActivated(uint64 activatedAt);
event InterestPaid(uint32 indexed cursor, uint256 amount);
event CollateralSeized(
  uint32 indexed cursor,
  uint256 missedUsd,
  uint256 seizedCollateral
);
event LoanDefaulted(uint16 missedCount, uint64 at);
event DefaultSeized(uint256 amount);
event LenderReimbursed(uint256 mTokenAmount);
event LoanSettled();
```

---

## 10. Custom errors

Use custom errors throughout (cheaper than `require` strings since Solidity
0.8.4).

```solidity
error Unauthorized();
error Paused();
error NotInitialized();
error AlreadyInitialized();
error OfferNotActive();
error RequestNotActive();
error OfferExpired();
error RequestExpired();
error BackendTermsExpired();
error WrongChain();
error WrongFactory();
error NonceAlreadyUsed();
error InvalidSignature(address expected, address recovered);
error BoundsViolation(string which);
error NotMTokenWhitelisted();
error NotCollateralWhitelisted();
error NotPrincipalTokenWhitelisted();
error InsufficientLenderBalance();
error InsufficientCollateral(uint256 haveUsd1e18, uint256 requiredUsd1e18);
error InsufficientPrincipalForRepay(uint256 haveAmount, uint256 requiredAmount);
error InvalidOraclePrice();
error StaleOraclePrice();
error LoanNotActive();
error LoanNotDefaulted();
error PaymentNotDue();
error PaymentGraceNotElapsed();
error BorrowFailed(uint errorCode); // Moonwell returned non-zero
error RepayFailed(uint errorCode);
error EnterMarketsFailed(uint errorCode);
error InvalidImplementation();
error InvalidComptroller(); // constructor probe failed — likely passed impl instead of proxy
error InvalidBufferBps(); // setMinOriginationLtvBufferBps out of sane range
error OnlyOwnerOrGuardian(); // pause() caller is neither
error ZeroAddress();
```

---

## 11. Admin surface

Admin permissions split between the Temporal Governor (owner) and the pause
guardian. Parameter ranges should be validated inside each setter.

```solidity
// ─── Modifiers ────────────────────────────────────────────────────
modifier onlyOwner();              // OZ Ownable
modifier onlyOwnerOrGuardian() {
    if (msg.sender != owner() && msg.sender != pauseGuardian)
        revert OnlyOwnerOrGuardian();
    _;
}

// ─── Backend signer ───────────────────────────────────────────────
function setBackendSigner(address newSigner) external onlyOwner;
// revert ZeroAddress if newSigner == 0

// ─── Implementation pointer ───────────────────────────────────────
function setCreditLoanImplementation(address newImpl) external onlyOwner;
// revert if newImpl is not a contract or already been initialized as a regular loan.
// Factory should call newImpl.initialize(...) with sentinel values to lock it before storing.

// ─── mToken whitelist ─────────────────────────────────────────────
function whitelistMToken(address mToken, bool allowed) external onlyOwner;

// ─── Collateral whitelist ─────────────────────────────────────────
function whitelistCollateralToken(
  address token,
  AggregatorV3Interface feed
) external onlyOwner;
// revert if feed.latestRoundData returns invalid (answer <= 0 or updatedAt stale on current block)

function removeCollateralToken(address token) external onlyOwner;
// existing loans already reference the immutable feed address, so removal only
// affects future loan origination

// ─── Principal-token whitelist (for onchain LTV check) ────────────
function whitelistPrincipalToken(
  address token,
  AggregatorV3Interface feed
) external onlyOwner;
// same live-feed validation as whitelistCollateralToken

function removePrincipalToken(address token) external onlyOwner;
// only blocks NEW offers/matches; existing loans are unaffected

// ─── Oracle / LTV params ──────────────────────────────────────────
function setStalenessWindow(uint32 seconds_) external onlyOwner;
// sanity cap: revert if seconds_ > 7 days

function setMinOriginationLtvBufferBps(uint16 bufferBps) external onlyOwner;
// sanity cap: revert InvalidBufferBps if bufferBps < 100 or > 10_000
// (i.e. collateral must be worth ≥ 101% of principal; never more than 200%)

// ─── Default loan params ──────────────────────────────────────────
function setDefaultParams(
  uint32 gracePeriod,
  uint16 overSeizureBps,
  uint16 consecutiveMissesForDefault,
  uint16 marketplaceFeeBps
) external onlyOwner;
// sanity caps:
// - gracePeriod: max 7 days
// - overSeizureBps: max 5000 (50%)
// - consecutiveMissesForDefault: at least 1, max 10
// - marketplaceFeeBps: max 2000 (20%)

function setFeeRecipient(address recipient) external onlyOwner;
// revert ZeroAddress

// ─── Pause guardian ───────────────────────────────────────────────
function setPauseGuardian(address newGuardian) external onlyOwner;
// revert ZeroAddress

// ─── Pause / unpause ──────────────────────────────────────────────
function pause() external onlyOwnerOrGuardian;  // immediate, no delay
function unpause() external onlyOwner;           // owner-only (5-day cycle)
```

**Why `unpause` is owner-only.** If the guardian's key were also the unpause
key, an attacker who compromises the guardian could toggle pause/unpause at will
— noise, but possibly also a vector if some downstream system keys off the pause
state. Splitting the authority means guardian compromise blocks **origination**
until the Temporal Governor reacts (~5 days), which is a bounded, recoverable
worst case.

---

## 12. Security considerations

### 12.1 Reentrancy

Use OZ `ReentrancyGuard` on:

- `Factory.createLoan` (outer) — calls external ERC20s + delegates to clone
- `CreditLoan.makePayment` — external USDC transferFrom + potential callback via
  `_settle`
- `CreditLoan.claimMissedPayment` — external oracle read + external ERC20
  transfer
- `CreditLoan.seizeAll` — external ERC20 transfer

For `initialize` and `activate` the factory guards via `nonReentrant`; those are
only callable during `createLoan`.

### 12.2 Oracle safety

- Every price read checks `answer > 0` and
  `block.timestamp - updatedAt < stalenessWindow`.
- Staleness window is a factory admin parameter, snapshotted into the loan at
  init (existing loans keep their original window even if admin changes it).
- Chainlink feed decimals are read fresh per call by `_valueToUsd1e18` (§7.3)
  and normalized to 1e18. Cheap enough; avoids the staleness-of-cached-decimals
  footgun.
- **Origination now also reads feeds** (both collateral and principal). A stale
  or zero-price feed therefore blocks new loans by design — a deliberate
  safety/liveness trade that favors safety.
- At `whitelistCollateralToken` / `whitelistPrincipalToken` time, the setter
  does a live round-data probe so a misconfigured feed is caught at proposal
  execution rather than at first match.
- The whitelist probe also rejects feeds with `decimals() > 18`
  (`InvalidFeedDecimals`). `PriceLib.valueToUsd1e18` scales up via
  `10 ** (18 - feedDecimals)`, which would underflow-revert on loan origination
  if a >18-decimal feed ever slipped through. Chainlink on Base uses 8 or 18;
  the check is defensive.

### 12.3 Backend key compromise

- Governance can rotate via `setBackendSigner`.
- Rotation does not affect in-flight loans (they store their backend signer at
  origination, but that's only for auditability — the contract doesn't check the
  signer after init).
- `validUntil` on backend terms must be short-ish (recommend ≤ 1 hour) so a
  leaked key has limited replay window.
- Per-signer nonces block replay of the _same_ terms.
- **Scope of damage with a compromised key is bounded by §7.3's onchain LTV
  check.** Even with a valid backend signature an attacker cannot originate an
  undercollateralized loan — the factory re-prices both sides from the
  governance-curated Chainlink feeds and reverts if
  `collateralUsd < principalUsd * (1 + buffer)`. The attacker can only sign
  loans that would also be honored by a fresh signer at current oracle prices.
- If a compromise is suspected, the pause guardian can freeze origination in a
  single transaction while the Temporal Governor proposal to rotate
  `backendSigner` goes through its 5-day cycle.

### 12.4 Signature attacks

- Use OpenZeppelin `ECDSA.recover` (handles EIP-2098 compact sigs and reverts on
  malleable sigs by enforcing low-s)
- EIP-712 typed data prevents cross-contract replay (domain separator binds to
  chainId + verifyingContract)
- Nonce invalidation on cancel prevents re-posting the same signed offer after
  cancellation

### 12.5 Clone init front-running

`Clones.clone` + `initialize` is atomic within `createLoan` — same tx, no
external calls between them — so there is no cross-tx front-run window. But the
clone contract defends in depth anyway: `initialize` binds
`factory = msg.sender` rather than reading a caller-supplied field.

If the `createLoan` flow ever split across multiple txs (or some future code
path let a third party call `initialize` on a cloned-but-unset contract), the
attacker's best outcome is a clone whose `factory` is the attacker's own
address. That clone can never be registered in the real factory's `loans`
mapping and can never pass factory-only hooks on the real factory — it is an
orphan. After the first `initialize` call the `_initialized` flag prevents any
re-init.

### 12.6 Implementation hijack

The `CreditLoan` implementation itself must have `_initialized = true` from the
very start. Factory constructor initializes it with an all-zero sentinel
`InitParams` to flip the flag; `factory` on the impl ends up as the factory
contract address (because `msg.sender == factoryAddr` during the constructor
call). Without this lock, someone could call `initialize` on the impl address
and hijack storage that affects… actually, nothing, because clones have their
own storage via delegatecall. But it's still a clean-up that costs nothing.

### 12.7 Per-loan isolation (the key structural property)

Each loan's Moonwell position is independent. If loan A's collateral drops and
Moonwell liquidates it:

- Loan A's clone absorbs the liquidation — its mToken balance drops
- Lender A loses some of their pledged mTokens (the liquidator's seize)
- No other clone is affected
- The factory is unaffected (it never holds borrow positions)

### 12.8 Reorg safety

`Clones.clone` uses `CREATE`, which produces a deterministic address from
(deployer, nonce). The deployer is the factory, so the next loan's address
depends on the factory's state nonce at the moment of deployment. If a match is
reorg'd out, the address may differ on re-execution. Events carry the actual
clone address, so indexers will resolve correctly.

Consider `Clones.cloneDeterministic(salt)` with
`salt = keccak256(abi.encode(loanId, backendTerms.loanNonce))` for reorg-stable
addresses if the indexer benefits from this. Optional.

### 12.9 Spam and griefing

- Posting an offer or request costs gas → economic deterrent
- No onchain listing fee in MVP (would be a natural x402 layer at the CLI level)
- Nonce collision by an attacker reposting a signature is impossible: the nonce
  mapping is keyed on the signer address, and attackers can't sign as someone
  else

### 12.10 Liquidator opportunity

If a clone's Moonwell health drops below 1.0, an external Moonwell liquidator
can seize its collateral (which is the lender's mTokens — not the borrower's
non-Moonwell collateral). This is a real risk to the lender. Mitigations:

- Lender's own `minBorrowerCreditTier` filter lets them refuse risky borrowers
- Over-seizure on missed payments helps compensate
- Governance can exclude mTokens with volatile collateral factors

### 12.11 Borrowing caps

Moonwell's `Comptroller.borrowCaps` are enforced by Moonwell itself. The clone's
borrow will revert naturally if the cap is exceeded. No additional check needed.

### 12.12 Pause-guardian model

- The guardian can only pause, not unpause. A hostile or compromised guardian
  can therefore only inflict a _bounded_ denial-of-service: origination +
  order-book mutation are frozen until the Temporal Governor can unpause (~5
  days).
- Pause does **not** block existing loans' `makePayment`, `claimMissedPayment`,
  `seizeAll`, `repayLoanAfterDefault`, or `redeemAndReturn`. Borrowers can stay
  current and lenders can still enforce defaults during the pause — crucial
  because a pause during an active loan must not brick borrowers.
- Guardian rotation is owner-only (`setPauseGuardian`), so recovery from
  guardian compromise still goes through governance — there is no self-kick
  shortcut (the `kickGuardian`-after-duration mechanic from
  `ConfigurablePauseGuardian` is intentionally omitted here; we trade that
  self-heal for simpler semantics).

### 12.13 Settlement solvency

See §7.7 "Solvency note (APR floor)." In short: `_settle` can revert
(`InsufficientPrincipalForRepay`) if Moonwell's borrow APR outpaced the
marketplace APR over the term. That outcome is recoverable via the default path
(§7.6) and is **not** a path to lender loss — the clone's state is preserved,
the lender can inject additional `principalToken` via `repayLoanAfterDefault` to
close the Moonwell borrow, then reclaim mTokens with `redeemAndReturn`.

---

## 13. Test harness

### 13.1 Foundry config

Match `moonwell-contracts-v2`'s settings:

```toml
# foundry.toml
[profile.default]
solc = "0.8.19"
optimizer = true
optimizer_runs = 1
evm_version = "cancun"
src = "src"
test = "test"
out = "artifacts/foundry"

[rpc_endpoints]
base = "${BASE_RPC_URL}"
baseSepolia = "${BASE_SEPOLIA_RPC_URL}"
```

### 13.2 Fixture: forked Base with Moonwell live contracts

```solidity
// test/Fixture.t.sol
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import { CreditMarketplaceFactory } from "src/marketplace/CreditMarketplaceFactory.sol";
import { CreditLoan } from "src/marketplace/CreditLoan.sol";

contract Fixture is Test {
  // ─── Base mainnet addresses, sourced from chains/8453.json ────
  // Prefer `vm.parseJson*` or `proposals/Addresses.sol` in production tests;
  // constants here are for quick-read test ergonomics only.
  //
  // chains/8453.json field → value
  //   UNITROLLER             (Comptroller proxy; call into this)
  //   COMPTROLLER            (Comptroller implementation; do NOT call directly)
  //   TEMPORAL_GOVERNOR
  //   MOONWELL_USDC, MOONWELL_cbBTC
  //   CHAINLINK_BTC_USD
  //   PAUSE_GUARDIAN         (Moonwell's security-response multisig)
  address constant UNITROLLER_PROXY =
    0xfBb21d0380beE3312B33c4353c8936a0F13EF26C;
  address constant TEMPORAL_GOVERNOR =
    0x8b621804a7637b781e2BbD58e256a591F2dF7d51;
  address constant PAUSE_GUARDIAN = 0x5B710010586C1b728B047c3E42473c700eeA4026;
  address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
  address constant MUSDC = 0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22;
  address constant MCBBTC = 0xF877ACaFA28c19b96727966690b2f44d35aD5976;
  address constant CHAINLINK_BTC_USD =
    0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F;

  CreditMarketplaceFactory factory;
  CreditLoan loanImpl;

  address lender = makeAddr("lender");
  address borrower = makeAddr("borrower");
  address backendSignerEOA;
  uint256 backendSignerKey;
  address feeRecipient = makeAddr("feeRecipient");

  function setUp() public virtual {
    vm.createSelectFork(vm.envString("BASE_RPC_URL"), 28_000_000);

    (backendSignerEOA, backendSignerKey) = makeAddrAndKey("backend");

    loanImpl = new CreditLoan();

    factory = new CreditMarketplaceFactory({
      _temporalGovernor: TEMPORAL_GOVERNOR,
      _comptroller: UNITROLLER_PROXY, // ABI entrypoint = the Unitroller proxy
      _creditLoanImplementation: address(loanImpl),
      _backendSigner: backendSignerEOA,
      _feeRecipient: feeRecipient,
      _pauseGuardian: PAUSE_GUARDIAN
    });

    // Whitelist starting set under gov impersonation
    vm.startPrank(TEMPORAL_GOVERNOR);
    factory.whitelistMToken(MUSDC, true);
    factory.whitelistMToken(MCBBTC, true);
    factory.whitelistCollateralToken(
      USDC,
      AggregatorV3Interface(address(0x1234)) // mock USDC/USD feed for unit tests
    );
    factory.whitelistPrincipalToken(
      USDC,
      AggregatorV3Interface(address(0x1234)) // same mock — USDC is both a collateral and principal asset
    );
    factory.setStalenessWindow(3600);
    factory.setMinOriginationLtvBufferBps(1000); // collateral ≥ 110% of principal at origination
    factory.setDefaultParams({
      gracePeriod: 86400,
      overSeizureBps: 2000,
      consecutiveMissesForDefault: 2,
      marketplaceFeeBps: 500
    });
    vm.stopPrank();

    // Fund lender with mTokens by pranking an address that already has them
    // (or calling mToken.mint after supplying USDC)
    // Fund borrower with collateral similarly
    // Borrower approves factory for collateral; lender approves factory for mTokens
  }

  // Helper to sign an Offer with a given EOA key
  function _signOffer(
    Offer memory o,
    uint256 pk
  ) internal view returns (bytes memory) {
    bytes32 digest = factory.hashOfferTyped(o); // view helper exposing EIP-712 digest
    (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
    return abi.encodePacked(r, s, v);
  }

  // Similarly _signRequest, _signBackendTerms
}
```

### 13.3 Core invariants (asserted in every test after loan activity)

```
for each settled loan:
    assert lender received mTokenAmount + (totalInterestPaid * (10000 - marketplaceFeeBps) / 10000)
    assert borrower received (principal) at activation and (collateralAmount - seizedCollateralAmount) at settle
    assert feeRecipient received (totalInterestPaid * marketplaceFeeBps / 10000)
    assert MToken(mToken).borrowBalanceStored(clone) == 0

for each clone:
    assert clone.status ∈ {Active, Settled, Defaulted, Closed}
    assert clone.seizedCollateralAmount <= clone.collateralAmount
```

### 13.4 Test matrix

| Suite       | Name                                                   | What it proves                                                                                                      |
| ----------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- |
| Happy path  | `test_fullLoanLifecycle_paysAllInstallmentsAndSettles` | Post, match, pay all interest, pay principal, settle. All invariants hold.                                          |
| Happy path  | `test_match_atomicityAndEvents`                        | All events emitted in correct order; reverts rollback all state.                                                    |
| Clawback    | `test_missOneInterestPayment_partialSeize`             | Miss 1 interest, clawback happens, missedCount = 1, loan still Active.                                              |
| Clawback    | `test_missTwoInterestPayments_accelerates`             | consecutiveMissesForDefault = 2 → status = Defaulted after second miss.                                             |
| Clawback    | `test_defaultThenSeizeAll_lenderGetsRemainder`         | After default, seizeAll transfers remaining collateral.                                                             |
| Clawback    | `test_defaultThenUnwindMoonwell_zerosBorrow`           | Lender can repay Moonwell via repayLoanAfterDefault + redeemAndReturn.                                              |
| Signatures  | `test_invalidBackendSig_reverts`                       | Wrong backend key → createLoan reverts.                                                                             |
| Signatures  | `test_expiredBackendTerms_reverts`                     | validUntil in past → revert.                                                                                        |
| Signatures  | `test_nonceReplay_reverts`                             | Re-using a consumed nonce → revert.                                                                                 |
| Signatures  | `test_termsOutOfOfferBounds_reverts`                   | backendTerms.apr > offer.maxApr → revert.                                                                           |
| Signatures  | `test_chainIdMismatch_reverts`                         | terms.chainId != block.chainid → revert.                                                                            |
| Signatures  | `test_factoryMismatch_reverts`                         | terms.factory != factory address → revert.                                                                          |
| Oracle      | `test_stalePrice_reverts`                              | Feed updatedAt too old → claimMissedPayment reverts.                                                                |
| Oracle      | `test_zeroPrice_reverts`                               | Feed answer <= 0 → revert.                                                                                          |
| Governance  | `test_rotateBackendSigner_affectsNewMatches`           | After rotation, old signer cannot authorize new loans.                                                              |
| Governance  | `test_rotateBackendSigner_doesNotAffectExistingLoans`  | Existing Active loans still operate normally.                                                                       |
| Governance  | `test_whitelistNewCollateral_enablesNewLoans`          |                                                                                                                     |
| Governance  | `test_pauseBlocksCreateLoan`                           | When paused, new matches revert; existing loans can still `makePayment`.                                            |
| Governance  | `test_setCreditLoanImplementation_newLoansUseNewImpl`  | Old clones still delegatecall to old impl.                                                                          |
| Moonwell    | `test_liquidationOfOneLoan_doesNotAffectOthers`        | Directly simulate a Moonwell liquidation against one clone via pranking; assert other clones unchanged.             |
| Security    | `test_initialize_onImplementation_reverts`             | Direct call to impl.initialize reverts AlreadyInitialized.                                                          |
| Security    | `test_reinitialize_onClone_reverts`                    | Second call to clone.initialize reverts AlreadyInitialized.                                                         |
| Security    | `test_constructor_wrongComptrollerAddress_reverts`     | Passing `COMPTROLLER` (implementation) instead of `UNITROLLER` (proxy) reverts `InvalidComptroller` at deploy time. |
| Onchain LTV | `test_createLoan_underCollateralizedAtOracle_reverts`  | §7.3 LTV check rejects when `collateralUsd < principalUsd × (1 + buffer)`.                                          |
| Onchain LTV | `test_createLoan_staleCollateralFeed_reverts`          | Feed older than `stalenessWindow` blocks origination.                                                               |
| Onchain LTV | `test_createLoan_stalePrincipalFeed_reverts`           | Same for the principal token's feed.                                                                                |
| Onchain LTV | `test_createLoan_unregisteredPrincipalFeed_reverts`    | Principal token without a `principalTokenFeeds` entry cannot originate.                                             |
| Onchain LTV | `test_createLoan_bufferZero_rejects110PctCollateral`   | Setting `minOriginationLtvBufferBps = 0` allows exact parity; setting to 1000 rejects ≤ 110%.                       |
| Cancel sigs | `test_cancelOffer_signatureBoundToDomainSeparator`     | Cancel sig from a different chainId / factory deployment is rejected (EIP-712 envelope check).                      |
| Cancel sigs | `test_cancelRequest_signatureBoundToDomainSeparator`   | Same for request cancellation.                                                                                      |
| Cancel sigs | `test_cancelOffer_nonceMismatch_reverts`               | Cancel sig that signs a different `nonce` than the stored offer's is rejected.                                      |
| Pause guard | `test_pauseGuardian_canPause`                          | Guardian pause succeeds and flips `paused()` true.                                                                  |
| Pause guard | `test_pauseGuardian_cannotUnpause`                     | Guardian unpause reverts `OnlyOwner` (not guardian).                                                                |
| Pause guard | `test_owner_canUnpauseAfterGuardianPause`              | Temporal Governor unpause succeeds post-guardian-pause.                                                             |
| Pause guard | `test_setPauseGuardian_onlyOwner`                      | Non-owner `setPauseGuardian` reverts.                                                                               |
| Pause guard | `test_pauseGuardian_cannotTouchOtherAdmin`             | Guardian calling `setBackendSigner`, `whitelistMToken`, etc. reverts.                                               |
| Pause guard | `test_pause_blocksCreateLoan_postOffer_postRequest`    | All four origination/mutation entrypoints revert when paused.                                                       |
| Pause guard | `test_pause_doesNotBlockExistingLoanMakePayment`       | Paused factory does NOT gate an existing clone's `makePayment` / `claimMissedPayment`.                              |
| Settle      | `test_settle_handlesAprDrift_repaysWithUintMax`        | When Moonwell APR > marketplace APR within tolerance, settle still works via the `type(uint).max` sentinel.         |
| Settle      | `test_settle_revertsOnInsufficientPrincipal`           | When shortage exceeds tolerance, settle reverts `InsufficientPrincipalForRepay` (not silent loss).                  |
| Settle      | `test_settle_forceApproveOverwritesResidualAllowance`  | Pre-existing non-zero allowance to mToken doesn't break repay.                                                      |
| Default     | `test_repayLoanAfterDefault_forceApproveResets`        | `repayLoanAfterDefault` works when mToken already has residual allowance from a prior partial repay.                |

---

## 14. Deployment

### 14.1 Constructor arguments

```solidity
CreditMarketplaceFactory(
    address _temporalGovernor,          // chains/<id>.json::TEMPORAL_GOVERNOR
    address _comptroller,               // chains/<id>.json::UNITROLLER (the Comptroller proxy)
    address _creditLoanImplementation,  // deploy CreditLoan first; pass its address
    address _backendSigner,             // TBD — Moonwell ops team generates a cold-key signer for prod
    address _feeRecipient,              // TBD — Moonwell treasury multisig
    address _pauseGuardian              // chains/<id>.json::PAUSE_GUARDIAN
)
```

Addresses MUST be read from `chains/<chainId>.json` (or
`proposals/Addresses.sol` for governance-driven deployments) per the repo's
address-management rule (`.claude/rules/proposals.md`). No hardcoded values in
scripts.

**Constructor sanity checks.** The constructor reverts on:

- any zero address (`ZeroAddress`);
- `_creditLoanImplementation` not being a contract, or not already
  `_initialized == true` (`InvalidImplementation`) — see §6.3;
- `_comptroller` not pointing at a live Comptroller proxy. Cheap probe:

  ```solidity
  // Belt-and-suspenders: catches operator passing the `COMPTROLLER`
  // (implementation) address instead of `UNITROLLER` (proxy) from
  // chains/<id>.json. The implementation has no state, so markets are
  // empty; a healthy Unitroller always has ≥ 1 listed market on any
  // chain we deploy to.
  if (ComptrollerInterface(_comptroller).getAllMarkets().length == 0)
      revert InvalidComptroller();
  ```

  Bricks deploy on the bad address rather than letting the first `createLoan`
  fail mid-match.

### 14.2 Deployment script sketch

```solidity
// script/Deploy.s.sol
pragma solidity 0.8.19;

import "forge-std/Script.sol";
import { Addresses } from "@proposals/Addresses.sol";
import { CreditMarketplaceFactory } from "src/marketplace/CreditMarketplaceFactory.sol";
import { CreditLoan } from "src/marketplace/CreditLoan.sol";

contract Deploy is Script {
  function run() external {
    // Source of truth is chains/<chainId>.json via proposals/Addresses.sol.
    // Scripts MUST NOT hardcode chain-specific addresses
    // (.claude/rules/proposals.md).
    Addresses addresses = new Addresses();

    address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
    address comptroller = addresses.getAddress("UNITROLLER");
    address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
    address backendSigner = vm.envAddress("BACKEND_SIGNER");
    address feeRecipient = vm.envAddress("FEE_RECIPIENT");

    vm.startBroadcast();

    CreditLoan loanImpl = new CreditLoan();
    CreditMarketplaceFactory factory = new CreditMarketplaceFactory(
      temporalGovernor,
      comptroller,
      address(loanImpl),
      backendSigner,
      feeRecipient,
      pauseGuardian
    );

    // Governance still needs to whitelist mTokens + collateral feeds +
    // principal-token feeds, and set `minOriginationLtvBufferBps`, after
    // deploy via Temporal Governor proposals. Deploy script does NOT do
    // this — ops responsibility (see §14.3).

    vm.stopBroadcast();

    console.log("CreditLoan impl at:", address(loanImpl));
    console.log("CreditMarketplaceFactory at:", address(factory));
  }
}
```

### 14.3 Post-deploy governance checklist

After mainnet deploy, a governance proposal should:

1. Call `factory.whitelistMToken(mUSDC, true)` and for every other supported
   mToken.
2. Call `factory.whitelistCollateralToken(collateralA, feedA)` for each approved
   collateral (live feed probed at setter time).
3. Call `factory.whitelistPrincipalToken(USDC, usdcUsdFeed)` for every principal
   token that will be offered (required before any `postOffer` succeeds).
4. Call `factory.setMinOriginationLtvBufferBps(1000)` (or the chosen value; see
   §17 appendix / open parameter questions).
5. Call `factory.setDefaultParams(...)` with production values.
6. Verify `factory.backendSigner()` is the expected ops key.
7. Verify `factory.feeRecipient()` is the treasury multisig.
8. Verify `factory.pauseGuardian()` matches `chains/<id>.json::PAUSE_GUARDIAN`.
   If a new guardian is being introduced (e.g., for Optimism before its
   canonical guardian is designated), the proposal MUST call
   `factory.setPauseGuardian(...)` explicitly rather than leaving a sentinel.

---

## 15. PR sequence

Each PR is designed to be reviewable independently. Any can be broken up
further.

| #   | Title                                                      | Contents                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    | Tests                                                                                                                                                                                                                           |
| --- | ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | --- | ------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Skeleton + test harness                                    | Directory layout under `src/marketplace/` and `test/marketplace/`. Interfaces (`ICreditMarketplaceFactory`, `ICreditLoan`). Stub `CreditMarketplaceFactory` and `CreditLoan` with all functions reverting `NotImplemented`. Foundry fixture that forks Base at a pinned block, deploys stubs, impersonates Temporal Governor.                                                                                                                                                                                                                               | Fixture loads successfully. Impersonation works.                                                                                                                                                                                |
| 2   | Factory admin + EIP-712 infrastructure                     | Ownable + Pausable wiring. Pause guardian role (`pauseGuardian`, `setPauseGuardian`, `onlyOwnerOrGuardian` modifier). Domain separator construction. Type hashes as constants (including `OFFER_CANCEL_TYPEHASH`, `REQUEST_CANCEL_TYPEHASH`). `_hashOffer`, `_hashRequest`, `_hashBackendTerms`, `_hashPaymentSchedule`, `_hashOfferCancel`, `_hashRequestCancel` helpers. `usedNonces` storage + `_consumeNonce`. All admin setters (`setBackendSigner`, `whitelistMToken`, `whitelistPrincipalToken`, `setMinOriginationLtvBufferBps`, etc.) with events. | Each owner-only setter reverts for non-owner. Guardian can pause; guardian cannot unpause or touch other admin. Domain hash matches computed value. Nonce consumption is idempotent.                                            |
| 3   | Offer + request CRUD                                       | `postOffer`, `cancelOffer`, `postRequest`, `cancelRequest`. Signature verification using the full `"\x19\x01"                                                                                                                                                                                                                                                                                                                                                                                                                                               |                                                                                                                                                                                                                                 | DOMAIN_SEPARATOR |     | structHash` envelope — including the cancel typehashes (§5.5) so cancel sigs are bound to chainId/factory/nonce. Status transitions. | Happy-path post + read. Invalid signature reverts. Expired offer reverts on post. Canceled offer cannot be re-matched (nonce burned). Cancel sig from a different chainId/factory is rejected. |
| 4   | `CreditLoan.initialize` + `activate`                       | `InitParams` struct. `initialize` with init guard. `activate` that calls `comptroller.enterMarkets`, `mToken.borrow`, `IERC20.transfer` to borrower. Status transitions.                                                                                                                                                                                                                                                                                                                                                                                    | Init guard blocks re-init. Activate can only be called by factory. Moonwell return codes checked.                                                                                                                               |
| 5   | `Factory.createLoan` end-to-end                            | Full match flow per §7.3, including the onchain LTV check (both `collateralFeeds` and `principalTokenFeeds` consulted, value normalized via `_valueToUsd1e18`, rejected when `collateralUsd < principalUsd * (1 + minOriginationLtvBufferBps) / 10_000`). Deploys clone, pulls funds, activates.                                                                                                                                                                                                                                                            | Happy-path match creates clone, transfers funds, emits `LoanCreated`. All sig/bounds failure modes revert. Stale feed or under-collateralized request reverts before any state change.                                          |
| 6   | `CreditLoan.makePayment` + schedule helpers                | `_interestDueAt`. `makePayment`. Interest accrual. Transition to final payment.                                                                                                                                                                                                                                                                                                                                                                                                                                                                             | Interest payments within window succeed. Late payment (past grace) reverts. Final payment triggers `_settle`.                                                                                                                   |
| 7   | `CreditLoan.claimMissedPayment` + oracle integration       | Oracle read + staleness check. Seize math. `missedCount` increment. Acceleration trigger.                                                                                                                                                                                                                                                                                                                                                                                                                                                                   | Clawback seizes exact expected amount. Stale oracle reverts. Acceleration after `consecutiveMissesForDefault`.                                                                                                                  |
| 8   | `CreditLoan.seizeAll` + `_settle` + default unwind helpers | `seizeAll`. `_settle` (called from final payment) uses `forceApprove(type(uint).max)` + `repayBorrowBehalf(type(uint).max)` sentinel so it tolerates Moonwell APR drift; reverts `InsufficientPrincipalForRepay` cleanly when the clone can't cover the Moonwell borrow. `repayLoanAfterDefault` (also `forceApprove`), `redeemAndReturn`.                                                                                                                                                                                                                  | Happy-path settle. Settle handles small APR drift; reverts cleanly on large drift so the lender can unwind via the default path. Default unwind path (lender repays Moonwell, redeems mTokens). Invariants hold on every close. |
| 9   | Base Sepolia deployment script + integration test          | `script/Deploy.s.sol`. Integration test that runs against a forked Base Sepolia, posts an offer + request, matches, pays, settles.                                                                                                                                                                                                                                                                                                                                                                                                                          | End-to-end on testnet fork.                                                                                                                                                                                                     |
| 10  | Mainnet deployment readiness                               | Audit hardening (confirm reentrancy guards everywhere; confirm all Moonwell return codes checked). Gas benchmarking. Simulation against Base mainnet fork with real lender + real collateral. Deploy script for Base mainnet.                                                                                                                                                                                                                                                                                                                               | Gas report meets targets (< 500k for full match). All invariants hold on mainnet fork.                                                                                                                                          |

---

## 16. Known limitations & out-of-scope for MVP

- **Non-Moonwell collateral auto-liquidation.** Lender unwinds off-contract
  after default. Optional onchain DEX-router integration is a later enhancement.
- **Negotiation.** Offers and requests are take-it-or-leave-it matched by the
  backend. Counter-offers deferred.
- **Cross-chain lending.** Each chain is independent. No cross-chain collateral
  or principal.
- **Undercollateralized loans.** Phase 3e, requires legal review. Current MVP
  always enforces overcollateralization **on-chain at match time** via the §7.3
  Chainlink LTV check plus `minOriginationLtvBufferBps`.
- **Interest compounding.** Linear APR per term only. Real compounding deferred.
- **Partial fills of offers.** First match consumes the entire offer. Lender
  must re-post with residual capacity if they want to rent more.
- **Per-loan upgrade path.** Deliberate: terms frozen at init is a feature.
  Factory can point to a new `CreditLoan` impl for future loans, but existing
  clones are immutable forever.
- **EIP-1271 smart-account signers.** MVP requires EOAs for all three signing
  roles. Smart accounts are a later enhancement.
- **x402 integration.** Match-time x402 payments (e.g., a marketplace listing
  fee paid by the backend) are handled at the CLI / backend layer, not in these
  contracts.
- **Marketplace APR floor vs Moonwell borrow APR.** Not enforced on-chain at
  `createLoan`. Backend pricing must ensure the loan's APR exceeds the Moonwell
  borrow APR for `mToken` by a comfortable buffer for the loan's term; otherwise
  `_settle` can revert with `InsufficientPrincipalForRepay` and the lender
  unwinds via §7.6. This is a deliberate MVP simplification: encoding
  `InterestRateModel.getBorrowRate` reads into `createLoan` is straightforward
  but adds gas and an extra failure mode for well-priced loans, so we push the
  check off-chain.
- **Guardian self-heal.** Unlike `ConfigurablePauseGuardian` in `src/xWELL/`,
  there is no auto-kick-after-duration. A compromised guardian can keep
  origination paused until the Temporal Governor rotates it (~5-day cycle).
  Accepted trade for simpler semantics.

## Open parameter questions (flag inline in code comments, decide before mainnet)

- Initial `gracePeriod` — suggest 86400 (24h)
- Initial `overSeizureBps` — suggest 2000 (20% premium on missed USD)
- Initial `consecutiveMissesForDefault` — suggest 2
- Initial `marketplaceFeeBps` — suggest 500 (5% of interest) or 0 + turn on
  later
- Initial `stalenessWindow` — suggest 3600 (1h) for BTC/USD, USDC/USD class
  feeds
- Initial `minOriginationLtvBufferBps` — suggest 1000 (collateral must be worth
  ≥ 110% of principal in USD at match time)
- Initial principal-token whitelist — USDC on Base, with `chains/8453.json`'s
  USDC/USD Chainlink feed
- Initial collateral whitelist — start with cbBTC, WETH, and optionally
  USDC-as-collateral for a stable loan case
- Initial pause guardian — `chains/<id>.json::PAUSE_GUARDIAN` (already deployed
  on Base as `0x5B710010586C1b728B047c3E42473c700eeA4026`; Optimism needs its
  own designation)

---

## 17. Appendix — inline Moonwell interface reference

This appendix is an excerpt from `moonwell-fi/moonwell-contracts-v2` so the next
LLM does not need to clone that repo to continue. Treat these as the canonical
surfaces you'll interact with.

### 17.1 `MToken` + `MErc20Interface` (excerpted)

```solidity
abstract contract MToken is MTokenInterface, Exponential, TokenErrorReporter {
  address payable public admin;
  address payable public pendingAdmin;
  ComptrollerInterface public comptroller;
  uint public totalSupply;
  mapping(address => uint) internal accountTokens;

  // ERC20
  function transfer(address dst, uint256 amount) external returns (bool);
  function transferFrom(
    address src,
    address dst,
    uint256 amount
  ) external returns (bool);
  function approve(address spender, uint256 amount) external returns (bool);
  function balanceOf(address owner) external view returns (uint256);

  // State-mutating views
  function balanceOfUnderlying(address owner) external returns (uint);
  function borrowBalanceCurrent(address account) external returns (uint);
  function exchangeRateCurrent() public returns (uint);

  // Pure views
  function borrowBalanceStored(address account) public view returns (uint);
  function exchangeRateStored() public view returns (uint);
}

abstract contract MErc20 is MToken, MErc20Interface {
  address public underlying;

  function mint(uint mintAmount) external returns (uint);
  function redeem(uint redeemTokens) external returns (uint);
  function redeemUnderlying(uint redeemAmount) external returns (uint);

  // BORROW IS MSG.SENDER-ONLY — there is no borrowBehalf.
  function borrow(uint borrowAmount) external returns (uint);

  function repayBorrow(uint repayAmount) external returns (uint);
  function repayBorrowBehalf(
    address borrower,
    uint repayAmount
  ) external returns (uint);
}
```

### 17.2 `Comptroller` (relevant subset)

```solidity
contract Comptroller is /* ... */ {
    function enterMarkets(address[] calldata mTokens) external returns (uint[] memory);
    function exitMarket(address mToken) external returns (uint);

    function getAccountLiquidity(address account)
        external view returns (uint errorCode, uint liquidity1e18, uint shortfall1e18);

    function checkMembership(address account, address mToken) external view returns (bool);
    function getAllMarkets() external view returns (MToken[] memory);

    mapping(address => uint) public borrowCaps;
    mapping(address => uint) public supplyCaps;
}
```

Return codes on policy calls: `0 = no error`, nonzero = error. We do NOT revert
on a nonzero Moonwell error code automatically; we check the return and revert
with our own custom error (`BorrowFailed(uint)`, `RepayFailed(uint)`,
`EnterMarketsFailed(uint)`).

### 17.3 `ChainlinkOracle` (Moonwell wrapper — we don't call this directly, but it's what Comptroller uses)

```solidity
contract ChainlinkOracle is PriceOracle {
  function getUnderlyingPrice(MToken mToken) external view returns (uint256);
  // Returns 1e18-scaled USD price of the underlying, already normalized for underlying decimals

  function setFeed(string calldata symbol, address feed) external onlyAdmin;
  function setDirectPrice(address asset, uint256 price) external onlyAdmin;

  mapping(bytes32 => AggregatorV3Interface) internal feeds;
  mapping(address => uint256) internal prices;
  address public admin;
}
```

### 17.4 `AggregatorV3Interface` (Chainlink standard — what WE use for collateral prices)

```solidity
interface AggregatorV3Interface {
  function decimals() external view returns (uint8);
  function description() external view returns (string memory);
  function version() external view returns (uint256);

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function getRoundData(
    uint80 _roundId
  )
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}
```

USD-denominated Chainlink feeds typically use 8 decimals. Always read
`feed.decimals()` and normalize explicitly; do not hardcode `8`.

### 17.5 `TemporalGovernor` (we just need its address as `owner`)

```solidity
contract TemporalGovernor is ITemporalGovernor, Ownable, Pausable {
  IWormhole public immutable wormholeBridge;
  uint256 public immutable proposalDelay;

  function queueProposal(bytes memory VAA) external;
  function executeProposal(bytes memory VAA) external;
  function fastTrackProposalExecution(bytes memory VAA) external;
}
```

**Addresses (duplicate from §3.5 for ease of copy-paste):**

| Chain            | Address                                      |
| ---------------- | -------------------------------------------- |
| Base mainnet     | `0x8b621804a7637b781e2BbD58e256a591F2dF7d51` |
| Optimism mainnet | `0x17C9ba3fDa7EC71CcfD75f978Ef31E21927aFF3d` |
| Base Sepolia     | `0xc01EA381A64F8BE3bDBb01A7c34D809f80783662` |

### 17.6 `ERC20` (standard — use OZ's `IERC20` and `SafeERC20`)

```solidity
interface IERC20 {
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address to, uint256 amount) external returns (bool);
  function allowance(
    address owner,
    address spender
  ) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

interface IERC20Metadata is IERC20 {
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
}
```

Always use `SafeERC20.safeTransfer` / `safeTransferFrom` for transfers and
`SafeERC20.forceApprove` for approvals (available on OZ ≥ 4.9 / v5). **Do not
use `safeApprove`** — it is deprecated by OpenZeppelin because it reverts when
the current allowance is non-zero, which would brick our repay paths if an
earlier partial repay left residual allowance. Every approval in this spec uses
`forceApprove`.

### 17.7 `Clones` (OpenZeppelin EIP-1167 helper)

```solidity
library Clones {
  function clone(address implementation) internal returns (address instance);
  function cloneDeterministic(
    address implementation,
    bytes32 salt
  ) internal returns (address instance);
  function predictDeterministicAddress(
    address implementation,
    bytes32 salt,
    address deployer
  ) internal pure returns (address predicted);
}
```

Use `Clones.clone(impl)` by default. Use `cloneDeterministic` only if indexer
benefits from predictable addresses.

### 17.8 `ECDSA` (OpenZeppelin)

```solidity
library ECDSA {
  function recover(
    bytes32 hash,
    bytes memory signature
  ) internal pure returns (address);
  function recover(
    bytes32 hash,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) internal pure returns (address);
}
```

Reverts on invalid signatures (EIP-2 s-value check, zero-address recover).

## 18. Future extension — Phase 3e: undercollateralized reputation lending

The MVP spec above is fully **overcollateralized**: borrowers lock up collateral
worth more than the principal (enforced implicitly by the `overSeizureBps` math
and Chainlink pricing at match time). This is intentional for launch — no credit
bureau required, default losses are bounded by seizable collateral.

Phase 3e unlocks the bigger prize: **agents with no Moonwell-listed collateral
but with verifiable Moonwell behavioral history can borrow at partial or zero
collateralization**, priced off their credit tier. This is the direct consumer
of the credit bureau being built in `lunar-indexer` (see the Phase 1 / Phase 2
breakdown in the original
[x402 integration proposal](./2026-04-13-x402-integration.md)).

### 18.1 What changes vs MVP

| Dimension                   | MVP (overcollateralized)                        | Phase 3e (undercollateralized)                              |
| --------------------------- | ----------------------------------------------- | ----------------------------------------------------------- |
| Collateralization           | ≥ 100% of principal at Chainlink price          | Any ratio, possibly 0%, priced via credit tier              |
| Credit tier enforcement     | Advisory (`minBorrowerCreditTier` on offer)     | Load-bearing — tier bounds the max principal per            |
| collateral unit             |
| Signatures at match         | lender offer + borrower request + backend terms | **+ credit bureau attestation** (new, 4th signature)        |
| Default loss model          | Lender made whole by collateral seizure         | Partial — lender eats shortfall OR insurance pool covers    |
| On-default action           | `seizeAll` takes remaining collateral           | `seizeAll` + emit `CreditDefault` event → bureau downgrades |
| borrower's tier permanently |
| Onboarding friction         | Borrower just needs whitelisted collateral      | Borrower needs ≥ N days of clean Moonwell history (from the |
| bureau)                     |

### 18.2 Where the credit bureau plugs in

The credit bureau (lunar-indexer's `@moonwell-fi/mcp` Phase 1+2 endpoints) is
the **ground-truth input** for pricing and the **observability sink** for
repayment behavior. It integrates at three distinct points:

1. **Pre-match (off-chain).** The backend's pricing engine queries the
   borrower's credit profile (`/api/v1/credit/:accountAddress`) when building
   `BackendTerms`. Tier + historical health factor + active-days drive the APR
   and

2. **Match time (on-chain).** The backend includes a fresh EIP-712 signed
   `CreditAttestation` (from `/api/v1/credit/attestation/:accountAddress`)
   alongside the existing three signatures. The factory verifies: - Attestation
   signer is the governance-whitelisted `creditBureauAttestor` -
   `attestation.subject == request.borrower` -
   `attestation.validUntil > block.timestamp` -
   `attestation.tier >= offer.minBorrowerCreditTier` - `attestation.reportHash`
   is bound into `BackendTerms` via an additional field (prevents re-using an
   old attestation with newer terms)

3. **Post-default (on-chain → off-chain).** On acceleration, the clone emits a
   `CreditDefault(borrower, principalOutstanding, interestOutstanding, collateralSeized, timestamp)`
   event. The lunar-indexer consumes it and materially affects the borrower's
   future credit reports (liquidation event, low repay ratio, tier downgrade).
   This closes the loop: reputation has real consequences.

### 18.3 New on-chain primitives

**Factory additions:**

```solidity
// New: a distinct signer role for the bureau.
// Could be the same EOA as backendSigner but conceptually separate — rotate independently.
address public creditBureauAttestor;

function setCreditBureauAttestor(address newAttestor) external onlyOwner;

bytes32 public constant CREDIT_ATTESTATION_TYPEHASH = keccak256(
    "CreditAttestation("
        "address subject,"
        "uint16 tier,"
        "uint16 score,"
        "bytes32 reportHash,"
        "uint64 issuedAt,"
        "uint64 validUntil"
    ")"
);

struct CreditAttestation {
    address subject;
    uint16 tier;
    uint16 score;
    bytes32 reportHash;
    uint64 issuedAt;
    uint64 validUntil;
}

BackendTerms gets one new field so replay of old attestations with new terms is impossible:

struct BackendTerms {
    // ... all existing fields ...
    bytes32 attestationReportHash;  // must equal CreditAttestation.reportHash
    uint16 minCollateralizationBps; // e.g. 5000 = 50%; 0 = uncollateralized; 10000+ = overcollateralized (still allowed)
}

createLoan gains a fourth signature parameter:

function createLoan(
    uint256 offerId,
    uint256 requestId,
    BackendTerms calldata terms,
    CreditAttestation calldata attestation,
    bytes calldata offerSig,
    bytes calldata requestSig,
    bytes calldata backendSig,
    bytes calldata attestationSig
) external returns (uint256 loanId, address loanAddress);

Clone emits a richer default event (in addition to existing LoanDefaulted):

event CreditDefault(
    address indexed borrower,
    uint256 principalOutstanding,
    uint256 interestOutstanding,
    uint256 collateralSeized,
    uint16 borrowerTierAtOrigination,
    uint64 at
);
```

### 18.4 Default loss absorption — the open design decision

When a loan is undercollateralized and defaults, something has to absorb the
loss between (seized collateral value) and (outstanding debt on Moonwell). Three
candidate models, listed in order of complexity:

1. Lender eats it. Simplest. Undercollateralization is priced entirely into the
   APR and the lender picks the tier floor they're comfortable with. No new
   infrastructure. The downside is that even one surprise default can wipe out
   many loans' interest income.
2. Insurance pool funded by fees. A portion of marketplaceFeeBps is routed to a
   coverage pool contract (a new CreditInsuranceVault). On undercollateralized
   defaults, the pool tops up the lender's shortfall up to some per-loan cap.
   Adds one contract; pool size is a governance knob.
3. Lender-staked coverage. Lenders wanting to underwrite undercollateralized
   loans must stake a coverage buffer separately. Complex; probably unnecessary
   for a launch phase.

Recommended starting point: option 1 for the very first undercollateralized
loans (tier prime only, ≥50% collateralized), then migrate to option 2 once
default data has validated pricing.

### 18.5 Changes needed in other layers

- Credit bureau (lunar-indexer). Must ship Phase 2 signed attestations before 3e
  can execute. The CreditAttestation struct above must match the backend-signed
  EIP-712 schema the bureau issues.
- Backend pricing engine. Must learn to price undercollateralized loans as a
  function of tier + requested ratio + market conditions. Expect iteration — the
  first month of undercollateralized loans is the calibration data.
- CLI. moonwell borrow request create needs a new flag for
  undercollateralization (or implicit: collateralAmount < principal triggers the
  attestation-required code path).
- Frontend. Surface the borrower's tier on every request; warn lenders when an
  offer can be filled by below-prime borrowers.

### 18.6 What does NOT change

- Factory contract storage and the per-loan clone layout stay compatible — 3e
  adds fields but doesn't remove or reorder anything, so the same factory can
  host both over- and undercollateralized loans.
- EIP-1167 clone isolation semantics are unchanged.
- Temporal Governor ownership is unchanged.
- The existing CreditLoan impl is forward-compatible: the factory can keep
  pointing at it for overcollateralized-only loans, and deploy a new
  CreditLoanV2 impl for undercollateralized ones. setCreditLoanImplementation
  was built for exactly this kind of evolution.

### 18.7 Rough PR sequence for 3e

Small list, will need refinement once Phase 2 of the credit bureau is live:

1. CreditInsuranceVault skeleton (if going with option 2) + governance wiring
2. CreditAttestation type hash + creditBureauAttestor role on factory + 4-sig
   createLoan variant
3. CreditLoanV2 impl: includes CreditDefault event emission and supports
   undercollateralized activation (no oracle-value check at match time)
4. Backend integration: attestation fetch + bundling with backend terms
5. Mainnet deploy + prime-tier-only beta launch

---

Phase 3e is where the credit bureau stops being a vanity metric and becomes a
real underwriting input. It's also where the legal posture changes —
undercollateralized agent-to-agent credit is more scrutinized territory, so
expect counsel involvement before launch.

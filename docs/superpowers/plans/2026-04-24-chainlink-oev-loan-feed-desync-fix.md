# ChainlinkOEV Loan Feed Desync Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the fresh-vs-delayed price desync in
`ChainlinkOEVWrapper._getLoanTokenPrice` and
`ChainlinkOEVMorphoWrapper._getLoanTokenPrice` by single-hop-dereferencing
OEV-wrapped registry feeds, and restore validation parity on the Morpho wrapper.

**Architecture:** Add a shared `IOEVWrapperFeed` interface and a per-wrapper
`_resolveRawFeed` helper that uses `try/catch` on `priceFeed()` to detect a
wrapper vs a raw aggregator. The collateral side is untouched. Then redeploy
`ChainlinkOEVWrapper` on Base + Optimism (non-upgradeable) and upgrade
`ChainlinkOEVMorphoWrapper` on Base (storage layout unchanged) via a cross-chain
MIP.

**Tech Stack:** Solidity 0.8.19, Foundry (`forge build`, `forge test`),
OpenZeppelin upgradeable proxies, Moonwell `HybridProposal` pattern.

**Spec:**
`docs/superpowers/specs/2026-04-24-chainlink-oev-loan-feed-desync-fix-design.md`

**Conventions reminder (project CLAUDE.md):**

- Run `forge build` after every `.sol` edit.
- Run `forge test` before committing contract changes.
- Never hardcode addresses — load from `proposals/Addresses.sol` or
  `chains/*.json`.
- New MIP entry: set `"id": 0` in `proposals/mips/mips.json`.
- `npm run prettier` to format before committing.

---

## File Structure

**New files:**

- `src/oracles/IOEVWrapperFeed.sol` — shared single-method interface used by
  `_resolveRawFeed` in both wrappers.
- `test/unit/ChainlinkOEVMorphoWrapperUnit.t.sol` — unit tests for the Morpho
  wrapper (doesn't exist today; mirror shape of `ChainlinkOEVWrapperUnit.t.sol`
  with a test harness subclass).
- `test/mock/MockOEVWrapperFeed.sol` — a small mock that exposes `priceFeed()`
  returning a configurable inner aggregator, plus
  `latestRoundData`/`decimals`/`description`/`version` pass-throughs.
- `proposals/mips/mip-x53/mip-x53.sol` — cross-chain MIP to redeploy Core
  wrappers and upgrade Morpho wrapper.
- `proposals/mips/mip-x53/x53.md` — human-readable description.
- `proposals/mips/mip-x53/x53.sh` — env var bootstrap script.

**Modified files:**

- `src/oracles/ChainlinkOEVWrapper.sol` — add `_resolveRawFeed` + update
  `_getLoanTokenPrice` + update docstring.
- `src/oracles/ChainlinkOEVMorphoWrapper.sol` — add `_resolveRawFeed` + update
  `_getLoanTokenPrice` (deref + `_validateRoundData`) + update docstring.
- `test/unit/ChainlinkOEVWrapperUnit.t.sol` — add deref tests.
- `test/integration/oracle/ChainlinkOEVWrapperIntegration.t.sol` — add deref
  regression integration test.
- `test/integration/oracle/ChainlinkOEVMorphoWrapperIntegration.t.sol` — add
  deref regression + validation-parity integration tests.
- `chains/8453.json` — add new `CHAINLINK_ETH_USD_OEV_WRAPPER` post-fix; rename
  prior to `_DEPRECATED_V3` (the `_DEPRECATED` suffix is already used for the
  pre-MIP-X38 wrapper).
- `chains/10.json` — same as 8453 for Optimism.
- `proposals/mips/mips.json` — new entry for mip-x53 with `"id": 0`.

Each file has one clear responsibility: the interface is one line; the deref
helper is one function; the unit tests exercise only `_getLoanTokenPrice`; the
MIP handles deployment + registration.

---

## Task 1: Shared interface

**Files:**

- Create: `src/oracles/IOEVWrapperFeed.sol`

- [ ] **Step 1: Create the interface file**

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "./AggregatorV3Interface.sol";

/// @title IOEVWrapperFeed
/// @notice Minimal interface exposed by Moonwell OEV wrappers so that
///         consumers can dereference a registered feed to its underlying
///         raw Chainlink aggregator.
/// @dev Both ChainlinkOEVWrapper and ChainlinkOEVMorphoWrapper already
///      satisfy this interface via their public `priceFeed` state variable.
interface IOEVWrapperFeed {
  function priceFeed() external view returns (AggregatorV3Interface);
}
```

- [ ] **Step 2: Build**

Run: `forge build` Expected: PASS (no new warnings beyond baseline for the new
file).

- [ ] **Step 3: Commit**

```bash
git add src/oracles/IOEVWrapperFeed.sol
git commit -m "feat(oracles): add IOEVWrapperFeed interface"
```

---

## Task 2: Mock for unit tests

**Files:**

- Create: `test/mock/MockOEVWrapperFeed.sol`

- [ ] **Step 1: Create the mock**

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import { AggregatorV3Interface } from "@protocol/oracles/AggregatorV3Interface.sol";

/// @notice Mock that pretends to be an OEV wrapper: exposes `priceFeed()`
///         returning a configurable inner aggregator, and proxies the rest
///         of AggregatorV3Interface to its own stored values.
contract MockOEVWrapperFeed is AggregatorV3Interface {
  AggregatorV3Interface public priceFeed;

  uint8 private _decimals;
  string private _description;
  uint256 private _version;

  uint80 public r_roundId;
  int256 public r_answer;
  uint256 public r_startedAt;
  uint256 public r_updatedAt;
  uint80 public r_answeredInRound;

  constructor(address inner, uint8 dec, string memory desc, uint256 ver) {
    priceFeed = AggregatorV3Interface(inner);
    _decimals = dec;
    _description = desc;
    _version = ver;
  }

  function setPriceFeed(address inner) external {
    priceFeed = AggregatorV3Interface(inner);
  }

  function setLatestRound(
    uint80 roundId,
    int256 answer,
    uint256 startedAt,
    uint256 updatedAt,
    uint80 answeredInRound
  ) external {
    r_roundId = roundId;
    r_answer = answer;
    r_startedAt = startedAt;
    r_updatedAt = updatedAt;
    r_answeredInRound = answeredInRound;
  }

  function decimals() external view override returns (uint8) {
    return _decimals;
  }

  function description() external view override returns (string memory) {
    return _description;
  }

  function version() external view override returns (uint256) {
    return _version;
  }

  function latestRound() external view override returns (uint256) {
    return uint256(r_roundId);
  }

  function getRoundData(
    uint80
  ) external view override returns (uint80, int256, uint256, uint256, uint80) {
    return (r_roundId, r_answer, r_startedAt, r_updatedAt, r_answeredInRound);
  }

  function latestRoundData()
    external
    view
    override
    returns (uint80, int256, uint256, uint256, uint80)
  {
    return (r_roundId, r_answer, r_startedAt, r_updatedAt, r_answeredInRound);
  }
}
```

- [ ] **Step 2: Build**

Run: `forge build` Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/mock/MockOEVWrapperFeed.sol
git commit -m "test: add MockOEVWrapperFeed for deref tests"
```

---

## Task 3: TDD — failing test for Core wrapper deref (raw path)

**Files:**

- Modify: `test/unit/ChainlinkOEVWrapperUnit.t.sol`

This test asserts that when the registry returns a **raw** aggregator (no
`priceFeed()` selector), the loan price reads directly from it.

- [ ] **Step 1: Read existing test file to find the harness pattern and
      imports**

Read `test/unit/ChainlinkOEVWrapperUnit.t.sol` and locate:

- The `ChainlinkOEVWrapperHarness` declaration (search:
  `contract ChainlinkOEVWrapperHarness`).
- The current `IChainlinkOracle` mock (search: `mockChainlinkOracle`).
- The exposed internal-function wrapper for `_getLoanTokenPrice` (search:
  `getLoanTokenPrice`). If it doesn't exist, you'll add it in Step 2.

- [ ] **Step 2: Ensure the harness exposes `_getLoanTokenPrice`**

At the bottom of the file (inside or alongside `ChainlinkOEVWrapperHarness`),
add:

```solidity
function exposed_getLoanTokenPrice(
  EIP20Interface underlyingLoan
) external view returns (uint256) {
  return _getLoanTokenPrice(underlyingLoan);
}
```

If the harness is defined out-of-line, locate it and add the external exposer.
Also add `exposed_resolveRawFeed` for future tests:

```solidity
function exposed_resolveRawFeed(
  AggregatorV3Interface registryFeed
) external view returns (AggregatorV3Interface) {
  return _resolveRawFeed(registryFeed);
}
```

- [ ] **Step 3: Add raw-path test**

Add to the test contract (after the existing tests, before the closing brace):

```solidity
function testLoanPriceReadsRawFeedWhenRegistryUnwrapped() public {
  // Deploy a plain MockChainlinkOracle as the raw loan feed.
  MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_000e8, 8);
  rawLoanFeed.set(1, 2_000e8, 1, block.timestamp, 1);

  // Point the ChainlinkOracle registry mock at the raw feed for the loan symbol.
  // loanToken is the `LOAN` MockERC20 from setUp().
  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(rawLoanFeed));

  uint256 priceScaled = harness.exposed_getLoanTokenPrice(
    EIP20Interface(address(loanToken))
  );

  // 2_000e8 -> 18 decimals scaling + loanToken is 18 decimals so tokenDecimals adjustment is a no-op
  assertEq(priceScaled, 2_000e18, "raw feed price not used");
}
```

(If `MockChainlinkOracle.setFeed` doesn't exist on the mock, check
`test/mock/MockChainlinkOracle.sol` for the actual symbol→feed wiring API and
use that.)

- [ ] **Step 4: Run the test — it MUST fail today (no harness exposer, or no
      `_resolveRawFeed`)**

Run:
`forge test --match-test testLoanPriceReadsRawFeedWhenRegistryUnwrapped -vvv`
Expected: FAIL with compile error (because `_resolveRawFeed` doesn't yet exist)
OR runtime FAIL.

If it PASSES before implementing, the test is wrong — stop and fix the test
first.

- [ ] **Step 5: Commit**

```bash
git add test/unit/ChainlinkOEVWrapperUnit.t.sol
git commit -m "test(oev-core): add raw-feed deref test (failing)"
```

---

## Task 4: Implement `_resolveRawFeed` + update `_getLoanTokenPrice` on Core wrapper

**Files:**

- Modify: `src/oracles/ChainlinkOEVWrapper.sol`

- [ ] **Step 1: Add the import**

At the top of the contract imports (around line 11), add:

```solidity
import { IOEVWrapperFeed } from "./IOEVWrapperFeed.sol";
```

- [ ] **Step 2: Add `_resolveRawFeed` helper**

Add immediately above `_getLoanTokenPrice` (before line 599):

```solidity
/// @notice Resolve a feed registered in ChainlinkOracle down to its raw
///         Chainlink aggregator, single-hop.
/// @dev If the registry feed is itself an OEV wrapper (exposes priceFeed()),
///      returns the inner aggregator. Otherwise returns the input unchanged.
///      Deliberately single-hop to avoid recursion and match the registry
///      invariant that entries are raw or a single level of wrapping.
function _resolveRawFeed(
  AggregatorV3Interface registryFeed
) internal view returns (AggregatorV3Interface) {
  try IOEVWrapperFeed(address(registryFeed)).priceFeed() returns (
    AggregatorV3Interface inner
  ) {
    if (address(inner) != address(0)) {
      return inner;
    }
  } catch {
    // registry feed is a raw aggregator (no priceFeed() selector);
    // fall through and return the input.
  }
  return registryFeed;
}
```

- [ ] **Step 3: Update `_getLoanTokenPrice`**

Replace the existing body of `_getLoanTokenPrice` (the function currently at
lines 599-640). New full body:

```solidity
/// @notice Get the loan token price from the raw underlying Chainlink feed.
/// @dev Single-hop dereferences any OEV wrapper registered under the loan
///      token's symbol in ChainlinkOracle, so the split math uses a
///      fresh-price reference regardless of OEV delay on the registry feed.
///      Restores parity with the collateral side which already reads the
///      raw `priceFeed` directly.
/// @param underlyingLoan The underlying loan token interface
/// @return The price scaled to 1e18 and adjusted for token decimals
function _getLoanTokenPrice(
  EIP20Interface underlyingLoan
) internal view returns (uint256) {
  AggregatorV3Interface registryFeed = chainlinkOracle.getFeed(
    underlyingLoan.symbol()
  );
  AggregatorV3Interface loanFeed = _resolveRawFeed(registryFeed);

  int256 loanAnswer;
  {
    (
      uint80 roundId,
      int256 answer,
      ,
      uint256 updatedAt,
      uint80 answeredInRound
    ) = loanFeed.latestRoundData();

    _validateRoundData(roundId, answer, updatedAt, answeredInRound);

    loanAnswer = answer;
  }

  // Scale feed decimals to 18 using the resolved feed's decimals.
  uint8 feedDecimals = loanFeed.decimals();
  uint256 loanPricePerUnit = uint256(loanAnswer);
  if (feedDecimals < 18) {
    loanPricePerUnit = loanPricePerUnit * (10 ** (18 - feedDecimals));
  } else if (feedDecimals > 18) {
    loanPricePerUnit = loanPricePerUnit / (10 ** (feedDecimals - 18));
  }

  // Adjust for token decimals (same logic as ChainlinkOracle).
  uint8 tokenDecimals = underlyingLoan.decimals();
  if (tokenDecimals < 18) {
    return loanPricePerUnit * (10 ** (18 - tokenDecimals));
  } else if (tokenDecimals > 18) {
    return loanPricePerUnit / (10 ** (tokenDecimals - 18));
  }
  return loanPricePerUnit;
}
```

- [ ] **Step 4: Build**

Run: `forge build` Expected: PASS.

- [ ] **Step 5: Run the raw-path test from Task 3**

Run:
`forge test --match-test testLoanPriceReadsRawFeedWhenRegistryUnwrapped -vvv`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/oracles/ChainlinkOEVWrapper.sol
git commit -m "fix(oev-core): single-hop deref loan feed to raw aggregator"
```

---

## Task 5: TDD — wrapped-path test on Core wrapper

**Files:**

- Modify: `test/unit/ChainlinkOEVWrapperUnit.t.sol`

Asserts that when the registry returns an OEV wrapper, `_getLoanTokenPrice` uses
the inner raw aggregator.

- [ ] **Step 1: Add the wrapped-path test**

```solidity
function testLoanPriceUsesInnerFeedWhenRegistryIsWrapper() public {
  // Inner (raw) feed: the "fresh" price
  MockChainlinkOracle innerRaw = new MockChainlinkOracle(3_000e8, 8);
  innerRaw.set(10, 3_000e8, 1, block.timestamp, 10);

  // Outer (OEV wrapper) feed: a stale price to prove we don't read it
  MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
    address(innerRaw),
    8,
    "MOCK_WRAPPER",
    1
  );
  outerWrapper.setLatestRound(9, 2_000e8, 1, block.timestamp - 600, 9);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(outerWrapper));

  uint256 priceScaled = harness.exposed_getLoanTokenPrice(
    EIP20Interface(address(loanToken))
  );

  // Must match the inner (3_000), not the outer (2_000).
  assertEq(priceScaled, 3_000e18, "wrapper was not dereferenced");
}
```

Add the import at the top of the file:

```solidity
import { MockOEVWrapperFeed } from "@test/mock/MockOEVWrapperFeed.sol";
```

- [ ] **Step 2: Run the test — must PASS**

Run:
`forge test --match-test testLoanPriceUsesInnerFeedWhenRegistryIsWrapper -vvv`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/unit/ChainlinkOEVWrapperUnit.t.sol
git commit -m "test(oev-core): wrapped-feed deref test"
```

---

## Task 6: TDD — defensive fallback when inner is zero

**Files:**

- Modify: `test/unit/ChainlinkOEVWrapperUnit.t.sol`

- [ ] **Step 1: Add the test**

```solidity
function testLoanPriceFallsBackToOuterWhenInnerIsZero() public {
  // Outer wrapper with inner = address(0) simulates a misconfigured wrapper.
  MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
    address(0),
    8,
    "MOCK_WRAPPER",
    1
  );
  outerWrapper.setLatestRound(1, 1_500e8, 1, block.timestamp, 1);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(outerWrapper));

  uint256 priceScaled = harness.exposed_getLoanTokenPrice(
    EIP20Interface(address(loanToken))
  );

  // Must fall back to outer's own round data (1_500).
  assertEq(priceScaled, 1_500e18, "defensive fallback not taken");
}
```

- [ ] **Step 2: Run**

Run: `forge test --match-test testLoanPriceFallsBackToOuterWhenInnerIsZero -vvv`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/unit/ChainlinkOEVWrapperUnit.t.sol
git commit -m "test(oev-core): fallback when inner priceFeed is zero"
```

---

## Task 7: TDD — single-hop only (no recursion)

**Files:**

- Modify: `test/unit/ChainlinkOEVWrapperUnit.t.sol`

- [ ] **Step 1: Add the test**

```solidity
function testDerefIsSingleHop() public {
  // inner-inner raw feed — this should NOT be reached.
  MockChainlinkOracle innerInner = new MockChainlinkOracle(9_999e8, 8);
  innerInner.set(1, 9_999e8, 1, block.timestamp, 1);

  // intermediate "wrapper-wrapping-a-wrapper" — this IS what should be read.
  MockOEVWrapperFeed middleWrapper = new MockOEVWrapperFeed(
    address(innerInner),
    8,
    "MIDDLE",
    1
  );
  middleWrapper.setLatestRound(1, 4_242e8, 1, block.timestamp, 1);

  // outer wrapper points at middle.
  MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
    address(middleWrapper),
    8,
    "OUTER",
    1
  );
  outerWrapper.setLatestRound(1, 1e8, 1, block.timestamp, 1);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(outerWrapper));

  uint256 priceScaled = harness.exposed_getLoanTokenPrice(
    EIP20Interface(address(loanToken))
  );

  // One hop: outer -> middle. Must be 4_242, not 9_999, not 1.
  assertEq(priceScaled, 4_242e18, "deref took more than one hop");
}
```

- [ ] **Step 2: Run**

Run: `forge test --match-test testDerefIsSingleHop -vvv` Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/unit/ChainlinkOEVWrapperUnit.t.sol
git commit -m "test(oev-core): deref is single-hop"
```

---

## Task 8: TDD — failing Morpho wrapper unit test file + raw-path test

**Files:**

- Create: `test/unit/ChainlinkOEVMorphoWrapperUnit.t.sol`

- [ ] **Step 1: Scaffold the Morpho unit test file**

Create the file with a harness that exposes `_getLoanTokenPrice` and a setUp
mirroring the OEV Core unit test:

```solidity
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import { Test } from "@forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ChainlinkOEVMorphoWrapper } from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import { AggregatorV3Interface } from "@protocol/oracles/AggregatorV3Interface.sol";
import { EIP20Interface } from "@protocol/EIP20Interface.sol";
import { MockChainlinkOracle } from "@test/mock/MockChainlinkOracle.sol";
import { MockERC20Decimals } from "@test/mock/MockERC20Decimals.sol";
import { MockOEVWrapperFeed } from "@test/mock/MockOEVWrapperFeed.sol";

/// @notice Test harness exposing internal helpers for unit tests.
contract ChainlinkOEVMorphoWrapperHarness is ChainlinkOEVMorphoWrapper {
  function exposed_getLoanTokenPrice(
    EIP20Interface loanToken
  ) external view returns (uint256) {
    return _getLoanTokenPrice(loanToken);
  }

  function exposed_resolveRawFeed(
    AggregatorV3Interface registryFeed
  ) external view returns (AggregatorV3Interface) {
    return _resolveRawFeed(registryFeed);
  }
}

contract ChainlinkOEVMorphoWrapperUnitTest is Test {
  address public owner = address(0x1);
  address public morphoBlue = address(0x2);
  address public feeRecipient = address(0x5);
  uint16 public defaultFeeBps = 100; // 1%
  uint256 public defaultMaxRoundDelay = 300;
  uint256 public defaultMaxDecrements = 5;

  MockChainlinkOracle mockPriceFeed;
  MockChainlinkOracle mockChainlinkOracle;
  MockERC20Decimals loanToken;

  ChainlinkOEVMorphoWrapperHarness harness;

  function setUp() public {
    mockPriceFeed = new MockChainlinkOracle(1e8, 8);
    mockPriceFeed.set(1, 1e8, 1, block.timestamp, 1);

    mockChainlinkOracle = new MockChainlinkOracle(1e8, 8);

    loanToken = new MockERC20Decimals("Loan", "LOAN", 18);

    // Deploy harness behind a proxy so the reinitializer path works.
    ChainlinkOEVMorphoWrapperHarness impl = new ChainlinkOEVMorphoWrapperHarness();
    bytes memory initData = abi.encodeWithSelector(
      ChainlinkOEVMorphoWrapper.initializeV2.selector,
      address(mockPriceFeed),
      owner,
      morphoBlue,
      address(mockChainlinkOracle),
      feeRecipient,
      defaultFeeBps,
      defaultMaxRoundDelay,
      defaultMaxDecrements
    );
    ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
    harness = ChainlinkOEVMorphoWrapperHarness(payable(address(proxy)));
  }

  function testLoanPriceReadsRawFeedWhenRegistryUnwrapped() public {
    MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(2_000e8, 8);
    rawLoanFeed.set(1, 2_000e8, 1, block.timestamp, 1);

    string memory loanSymbol = loanToken.symbol();
    mockChainlinkOracle.setFeed(loanSymbol, address(rawLoanFeed));

    uint256 priceScaled = harness.exposed_getLoanTokenPrice(
      EIP20Interface(address(loanToken))
    );
    assertEq(priceScaled, 2_000e18, "raw feed price not used");
  }
}
```

(If `MockChainlinkOracle` does not support `setFeed(symbol, address)`, read
`test/mock/MockChainlinkOracle.sol` and use the real registry API — adjust this
test and Task 3's test consistently.)

- [ ] **Step 2: Run — must fail (no deref on Morpho wrapper yet)**

Run:
`forge test --match-contract ChainlinkOEVMorphoWrapperUnitTest --match-test testLoanPriceReadsRawFeedWhenRegistryUnwrapped -vvv`
Expected: FAIL (compile error or runtime: `_resolveRawFeed` doesn't exist yet).

- [ ] **Step 3: Commit**

```bash
git add test/unit/ChainlinkOEVMorphoWrapperUnit.t.sol
git commit -m "test(oev-morpho): scaffold unit test + raw-path test (failing)"
```

---

## Task 9: Implement deref + validation parity on Morpho wrapper

**Files:**

- Modify: `src/oracles/ChainlinkOEVMorphoWrapper.sol`

- [ ] **Step 1: Add the import**

At the top imports (near line 13), add:

```solidity
import { IOEVWrapperFeed } from "./IOEVWrapperFeed.sol";
```

- [ ] **Step 2: Add `_resolveRawFeed` helper**

Insert immediately above `_getLoanTokenPrice` (before line 496):

```solidity
/// @notice Resolve a feed registered in ChainlinkOracle down to its raw
///         Chainlink aggregator, single-hop.
/// @dev If the registry feed is itself an OEV wrapper (exposes priceFeed()),
///      returns the inner aggregator. Otherwise returns the input unchanged.
function _resolveRawFeed(
  AggregatorV3Interface registryFeed
) internal view returns (AggregatorV3Interface) {
  try IOEVWrapperFeed(address(registryFeed)).priceFeed() returns (
    AggregatorV3Interface inner
  ) {
    if (address(inner) != address(0)) {
      return inner;
    }
  } catch {
    // registry feed is a raw aggregator; fall through.
  }
  return registryFeed;
}
```

- [ ] **Step 3: Replace `_getLoanTokenPrice` body**

Replace the full body of `_getLoanTokenPrice` with:

```solidity
/// @notice Get the loan token price from the raw underlying Chainlink feed.
/// @dev Single-hop dereferences any OEV wrapper registered under the loan
///      token's symbol, and applies the same `_validateRoundData` checks as
///      the collateral side to enforce non-zero answer, non-zero updatedAt,
///      and answeredInRound >= roundId.
/// @param loanToken The loan token interface
/// @return The price scaled to 1e18 and adjusted for token decimals
function _getLoanTokenPrice(
  EIP20Interface loanToken
) private view returns (uint256) {
  AggregatorV3Interface registryFeed = chainlinkOracle.getFeed(
    loanToken.symbol()
  );
  AggregatorV3Interface loanFeed = _resolveRawFeed(registryFeed);

  int256 loanAnswer;
  {
    (
      uint80 roundId,
      int256 answer,
      ,
      uint256 updatedAt,
      uint80 answeredInRound
    ) = loanFeed.latestRoundData();

    _validateRoundData(roundId, answer, updatedAt, answeredInRound);

    loanAnswer = answer;
  }

  uint8 feedDecimals = loanFeed.decimals();
  uint256 loanPricePerUnit = uint256(loanAnswer);
  if (feedDecimals < 18) {
    loanPricePerUnit = loanPricePerUnit * (10 ** (18 - feedDecimals));
  } else if (feedDecimals > 18) {
    loanPricePerUnit = loanPricePerUnit / (10 ** (feedDecimals - 18));
  }

  uint8 tokenDecimals = loanToken.decimals();
  if (tokenDecimals < 18) {
    return loanPricePerUnit * (10 ** (18 - tokenDecimals));
  } else if (tokenDecimals > 18) {
    return loanPricePerUnit / (10 ** (tokenDecimals - 18));
  }
  return loanPricePerUnit;
}
```

- [ ] **Step 4: Build**

Run: `forge build` Expected: PASS.

- [ ] **Step 5: Run Task 8 test**

Run: `forge test --match-contract ChainlinkOEVMorphoWrapperUnitTest -vvv`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add src/oracles/ChainlinkOEVMorphoWrapper.sol
git commit -m "fix(oev-morpho): deref loan feed + validate round data"
```

---

## Task 10: Morpho wrapper — wrapped-path, fallback, and validation-parity tests

**Files:**

- Modify: `test/unit/ChainlinkOEVMorphoWrapperUnit.t.sol`

- [ ] **Step 1: Add four more tests**

Append these inside the test contract:

```solidity
function testLoanPriceUsesInnerFeedWhenRegistryIsWrapper() public {
  MockChainlinkOracle innerRaw = new MockChainlinkOracle(3_000e8, 8);
  innerRaw.set(10, 3_000e8, 1, block.timestamp, 10);

  MockOEVWrapperFeed outerWrapper = new MockOEVWrapperFeed(
    address(innerRaw),
    8,
    "MOCK_WRAPPER",
    1
  );
  outerWrapper.setLatestRound(9, 2_000e8, 1, block.timestamp - 600, 9);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(outerWrapper));

  uint256 priceScaled = harness.exposed_getLoanTokenPrice(
    EIP20Interface(address(loanToken))
  );
  assertEq(priceScaled, 3_000e18, "wrapper was not dereferenced");
}

function testLoanPriceRevertsOnZeroUpdatedAt() public {
  MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
  // updatedAt = 0 triggers "Round is in incompleted state"
  rawLoanFeed.set(1, 1e8, 1, 0, 1);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(rawLoanFeed));

  vm.expectRevert("Round is in incompleted state");
  harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
}

function testLoanPriceRevertsOnStaleAnsweredInRound() public {
  MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
  // answeredInRound (1) < roundId (2) triggers "Stale price"
  rawLoanFeed.set(2, 1e8, 1, block.timestamp, 1);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(rawLoanFeed));

  vm.expectRevert("Stale price");
  harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
}

function testLoanPriceRevertsOnNonPositiveAnswer() public {
  MockChainlinkOracle rawLoanFeed = new MockChainlinkOracle(1e8, 8);
  rawLoanFeed.set(1, 0, 1, block.timestamp, 1);

  string memory loanSymbol = loanToken.symbol();
  mockChainlinkOracle.setFeed(loanSymbol, address(rawLoanFeed));

  vm.expectRevert("Chainlink price cannot be lower or equal to 0");
  harness.exposed_getLoanTokenPrice(EIP20Interface(address(loanToken)));
}
```

- [ ] **Step 2: Run**

Run: `forge test --match-contract ChainlinkOEVMorphoWrapperUnitTest -vvv`
Expected: PASS (all tests).

- [ ] **Step 3: Commit**

```bash
git add test/unit/ChainlinkOEVMorphoWrapperUnit.t.sol
git commit -m "test(oev-morpho): wrapped path + validation parity tests"
```

---

## Task 11: Core wrapper integration test on Base fork

**Files:**

- Modify: `test/integration/oracle/ChainlinkOEVWrapperIntegration.t.sol`

- [ ] **Step 1: Read current integration test layout**

Open the file and locate the existing test helper that does a live liquidation
(search for `updatePriceEarlyAndLiquidate`) and the pattern for obtaining the
wrapper from `addresses`.

- [ ] **Step 2: Add deref regression test**

Add a new test that verifies `_resolveRawFeed` behavior end-to-end on fork by
introspecting the wrapper:

```solidity
function testLoanFeedDerefMatchesRawChainlinkAggregator() public {
  // Skip unless on Base (wrapper is Base-only for WETH here).
  if (block.chainid != 8453) return;

  address wrapperAddr = addresses.getAddress("CHAINLINK_ETH_USD_OEV_WRAPPER");
  ChainlinkOEVWrapper wrapper = ChainlinkOEVWrapper(payable(wrapperAddr));

  // Walk the registry for a known loan symbol (USDC).
  AggregatorV3Interface registered = wrapper.chainlinkOracle().getFeed("USDC");

  // If the registry entry is itself an OEV wrapper, priceFeed() must
  // dereference to a non-zero raw aggregator; otherwise the registered
  // feed itself must be a contract.
  try IOEVWrapperFeed(address(registered)).priceFeed() returns (
    AggregatorV3Interface inner
  ) {
    assertTrue(
      address(inner) != address(0),
      "registered wrapper has zero inner feed"
    );
    // Sanity: inner is a contract.
    uint256 codeLen;
    address a = address(inner);
    assembly {
      codeLen := extcodesize(a)
    }
    assertGt(codeLen, 0, "inner feed has no code");
  } catch {
    // Not a wrapper — must still be a live contract.
    uint256 codeLen;
    address a = address(registered);
    assembly {
      codeLen := extcodesize(a)
    }
    assertGt(codeLen, 0, "registered feed has no code");
  }
}
```

Add to the imports at top of the file:

```solidity
import { IOEVWrapperFeed } from "@protocol/oracles/IOEVWrapperFeed.sol";
import { AggregatorV3Interface } from "@protocol/oracles/AggregatorV3Interface.sol";
```

- [ ] **Step 3: Run**

Run:
`PRIMARY_FORK_ID=8453 forge test --match-contract ChainlinkOEVWrapperIntegrationTest --match-test testLoanFeedDerefMatchesRawChainlinkAggregator -vvv`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add test/integration/oracle/ChainlinkOEVWrapperIntegration.t.sol
git commit -m "test(oev-core-integration): deref regression on Base fork"
```

---

## Task 12: Morpho wrapper integration test on Base fork

**Files:**

- Modify: `test/integration/oracle/ChainlinkOEVMorphoWrapperIntegration.t.sol`

- [ ] **Step 1: Add deref regression test**

Append to the test contract:

```solidity
function testLoanFeedDerefProducesNonZeroPrice() public {
  for (uint256 i = 0; i < wrappers.length; i++) {
    ChainlinkOEVMorphoWrapper wrapper = wrappers[i];
    // For the WELL/USDC market on Base, loan token is USDC.
    if (block.chainid != 8453) continue;

    AggregatorV3Interface registered = wrapper.chainlinkOracle().getFeed(
      "USDC"
    );

    // Drive through the public read path: call latestRoundData on the
    // resolved feed to ensure it reverts on the raw path when the
    // registry points at a wrapper with OEV delay.
    try IOEVWrapperFeed(address(registered)).priceFeed() returns (
      AggregatorV3Interface inner
    ) {
      (, int256 ans, , uint256 updatedAt, ) = inner.latestRoundData();
      assertGt(ans, 0, "inner feed answer not positive");
      assertGt(updatedAt, 0, "inner feed updatedAt is zero");
    } catch {
      (, int256 ans, , uint256 updatedAt, ) = registered.latestRoundData();
      assertGt(ans, 0, "registered feed answer not positive");
      assertGt(updatedAt, 0, "registered feed updatedAt is zero");
    }
  }
}
```

Add to imports at top:

```solidity
import { IOEVWrapperFeed } from "@protocol/oracles/IOEVWrapperFeed.sol";
import { AggregatorV3Interface } from "@protocol/oracles/AggregatorV3Interface.sol";
```

- [ ] **Step 2: Run**

Run:
`PRIMARY_FORK_ID=8453 forge test --match-contract ChainlinkOEVMorphoWrapperIntegrationTest --match-test testLoanFeedDerefProducesNonZeroPrice -vvv`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add test/integration/oracle/ChainlinkOEVMorphoWrapperIntegration.t.sol
git commit -m "test(oev-morpho-integration): deref regression on Base fork"
```

---

## Task 13: Full test suite sanity pass before moving to the MIP

- [ ] **Step 1: Run unit tests**

Run: `make test-unit` Expected: PASS.

- [ ] **Step 2: Run integration tests for oracle subtree on Base fork**

Run:
`PRIMARY_FORK_ID=8453 forge test --match-path "test/integration/oracle/*" -vvv`
Expected: PASS.

- [ ] **Step 3: Run integration tests on Optimism fork**

Run:
`PRIMARY_FORK_ID=10 forge test --match-path "test/integration/oracle/*" -vvv`
Expected: PASS.

- [ ] **Step 4: Prettier + Slither hygiene**

Run: `npm run prettier && make slither` Expected: Prettier formats without
meaningful changes; Slither output matches baseline (no new findings on the
touched contracts).

- [ ] **Step 5: If any formatting changes, commit**

```bash
git add -u
git commit -m "chore: prettier formatting" || true
```

---

## Task 14: MIP scaffold (mip-x53)

**Files:**

- Create: `proposals/mips/mip-x53/x53.sh`
- Create: `proposals/mips/mip-x53/x53.md`
- Create: `proposals/mips/mip-x53/mip-x53.sol`
- Modify: `proposals/mips/mips.json`

- [ ] **Step 1: Shell env**

Create `proposals/mips/mip-x53/x53.sh`:

```bash
#!/usr/bin/env bash

export DESCRIPTION_PATH="proposals/mips/mip-x53/x53.md"
export JSON_PATH="proposals/mips/mip-x53/mip-x53.sol/mipx53.json"
export PRIMARY_FORK_ID=1
```

Then `chmod +x proposals/mips/mip-x53/x53.sh`.

- [ ] **Step 2: Markdown description**

Create `proposals/mips/mip-x53/x53.md`:

```markdown
# MIP-X53: Fix Chainlink OEV Loan-Feed Desync

## Summary

Deploys new `ChainlinkOEVWrapper` contracts on Base and Optimism and upgrades
the Base `ChainlinkOEVMorphoWrapper` implementation. Each change addresses a
loan-vs-collateral price desync discovered in the Moonwell bug bounty program
(code-423n4/moonwell-bug-bounty-submissions#150).

The fix dereferences any OEV wrapper registered under the loan token's symbol
down to its raw Chainlink aggregator before reading `latestRoundData()`, so the
liquidation fee split uses the same freshness reference on both sides.

The Morpho wrapper change additionally restores validation parity with the Core
wrapper: `updatedAt != 0` and `answeredInRound >= roundId` are now enforced on
the loan feed.

## Impact

Medium-severity finding acknowledged by the sponsor as a goodwill bounty. No
funds at risk. Affects only the liquidator/protocol fee split accuracy.

## Actions

### Base

- Deploy a new `ChainlinkOEVWrapper` for WETH/ETH with the same parameters as
  MIP-X38 (`liquidatorFeeBps=4000`, `maxRoundDelay=10`, `maxDecrements=10`).
- `ChainlinkOracle.setFeed("WETH", newWrapper)`.
- Upgrade `ChainlinkOEVMorphoWrapper` proxy implementation. No `reinitializer` —
  storage layout unchanged.

### Optimism

- Deploy a new `ChainlinkOEVWrapper` for WETH/ETH with matching parameters.
- `ChainlinkOracle.setFeed("WETH", newWrapper)`.

## Parameters preserved

| Parameter        | Value |
| ---------------- | ----- |
| liquidatorFeeBps | 4000  |
| maxRoundDelay    | 10    |
| maxDecrements    | 10    |
```

- [ ] **Step 3: mips.json entry**

Read the file, then append (keeping the array valid JSON) an entry mirroring the
`mip-x52` entry layout:

```json
{
  "path": "mip-x53.sol/mipx53.json",
  "proposalsFolder": "proposals/mips/mip-x53/",
  "name": "mipx53",
  "id": 0,
  "envpath": "proposals/mips/mip-x53/x53.sh"
}
```

(Leave existing entries unchanged. Check `envpath` vs `envPath` in the file —
the project has both historically; match the immediate-neighbor casing.)

- [ ] **Step 4: Build**

Run: `forge build` Expected: PASS (no MIP contract yet — skip if forge errors on
missing .sol; create the .sol in Task 15 first then build).

- [ ] **Step 5: Commit scaffolding**

```bash
git add proposals/mips/mip-x53/x53.sh proposals/mips/mip-x53/x53.md proposals/mips/mips.json
git commit -m "chore(mip-x53): scaffold proposal files"
```

---

## Task 15: MIP contract — deploy, build, validate

**Files:**

- Create: `proposals/mips/mip-x53/mip-x53.sol`

- [ ] **Step 1: Read a recent HybridProposal that does both a cross-chain
      redeploy and a proxy upgrade, for reference**

Read `proposals/mips/mip-x52/mip-x52.sol` and `proposals/mips/mip-x50/` (if
present) to learn the patterns for:

- selecting forks per chain
- registering deployed addresses via `addresses.addAddress`
- constructing `_pushAction` for `ChainlinkOracle.setFeed` calls on Base and
  Optimism
- constructing `_pushAction` for `ProxyAdmin.upgrade(proxy, newImpl)` on Base

Take notes — the exact helpers vary by proposal type.

- [ ] **Step 2: Write the MIP contract**

```solidity
//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import { ITransparentUpgradeableProxy } from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import { HybridProposal } from "@proposals/proposalTypes/HybridProposal.sol";
import { AllChainAddresses as Addresses } from "@proposals/Addresses.sol";
import { MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ChainIds } from "@utils/ChainIds.sol";
import { ProposalActions } from "@proposals/utils/ProposalActions.sol";

import { ChainlinkOEVWrapper } from "@protocol/oracles/ChainlinkOEVWrapper.sol";
import { ChainlinkOEVMorphoWrapper } from "@protocol/oracles/ChainlinkOEVMorphoWrapper.sol";
import { ChainlinkOracle } from "@protocol/oracles/ChainlinkOracle.sol";

/// @title MIP-X53: Fix Chainlink OEV Loan-Feed Desync
/// @notice Redeploys ChainlinkOEVWrapper on Base and Optimism and upgrades
///         ChainlinkOEVMorphoWrapper on Base. Addresses a loan-vs-collateral
///         price desync bug (c4 bounty submission #150).
contract mipx53 is HybridProposal {
  using ProposalActions for *;
  using ChainIds for uint256;

  string public constant override name = "MIP-X53";

  uint16 public constant LIQUIDATOR_FEE_BPS = 4000;
  uint256 public constant MAX_ROUND_DELAY = 10;
  uint256 public constant MAX_DECREMENTS = 10;

  constructor() {
    bytes memory proposalDescription = abi.encodePacked(
      vm.readFile("./proposals/mips/mip-x53/x53.md")
    );
    _setProposalDescription(proposalDescription);
  }

  function run() public override {
    primaryForkId().createForksAndSelect();

    Addresses addresses = new Addresses();
    vm.makePersistent(address(addresses));

    initProposal(addresses);

    (, address deployerAddress, ) = vm.readCallers();

    if (DO_DEPLOY) deploy(addresses, deployerAddress);
    if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

    if (DO_BUILD) build(addresses);
    if (DO_RUN) simulate(addresses, deployerAddress);
    if (DO_TEARDOWN) teardown(addresses, deployerAddress);
    if (DO_VALIDATE) {
      validate(addresses, deployerAddress);
      console.log("Validation completed for proposal ", this.name());
    }
    if (DO_PRINT) {
      printProposalActionSteps();
      addresses.removeAllRestrictions();
      printCalldata(addresses);
      _printAddressesChanges(addresses);
    }
  }

  function primaryForkId() public pure override returns (uint256) {
    return MOONBEAM_FORK_ID;
  }

  function deploy(Addresses addresses, address) public override {
    // --- Base: new ChainlinkOEVWrapper(WETH) ---
    vm.selectFork(BASE_FORK_ID);
    if (!addresses.isAddressSet("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")) {
      address feed = addresses.getAddress("CHAINLINK_ETH_USD_FEED");
      address oracle = addresses.getAddress("CHAINLINK_ORACLE");
      address recipient = addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER");
      address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");
      vm.startBroadcast();
      ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
        feed,
        tempGov,
        oracle,
        recipient,
        LIQUIDATOR_FEE_BPS,
        MAX_ROUND_DELAY,
        MAX_DECREMENTS
      );
      vm.stopBroadcast();
      addresses.addAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3",
        address(wrapper)
      );
    }

    // --- Base: new ChainlinkOEVMorphoWrapper implementation ---
    if (!addresses.isAddressSet("CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2")) {
      vm.startBroadcast();
      address impl = address(new ChainlinkOEVMorphoWrapper());
      vm.stopBroadcast();
      addresses.addAddress("CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2", impl);
    }

    // --- Optimism: new ChainlinkOEVWrapper(WETH) ---
    vm.selectFork(OPTIMISM_FORK_ID);
    if (!addresses.isAddressSet("CHAINLINK_ETH_USD_OEV_WRAPPER_V3")) {
      address feed = addresses.getAddress("CHAINLINK_ETH_USD_FEED");
      address oracle = addresses.getAddress("CHAINLINK_ORACLE");
      address recipient = addresses.getAddress("OEV_PROTOCOL_FEE_REDEEMER");
      address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");
      vm.startBroadcast();
      ChainlinkOEVWrapper wrapper = new ChainlinkOEVWrapper(
        feed,
        tempGov,
        oracle,
        recipient,
        LIQUIDATOR_FEE_BPS,
        MAX_ROUND_DELAY,
        MAX_DECREMENTS
      );
      vm.stopBroadcast();
      addresses.addAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3",
        address(wrapper)
      );
    }
  }

  function build(Addresses addresses) public override {
    // Base actions
    vm.selectFork(BASE_FORK_ID);
    {
      address oracle = addresses.getAddress("CHAINLINK_ORACLE");
      address newWrapper = addresses.getAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3"
      );
      _pushAction(
        oracle,
        abi.encodeWithSignature("setFeed(string,address)", "WETH", newWrapper),
        "Base: ChainlinkOracle.setFeed(WETH, new OEV wrapper)"
      );

      address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
      address proxy = addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY");
      address impl = addresses.getAddress(
        "CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2"
      );
      _pushAction(
        proxyAdmin,
        abi.encodeWithSelector(
          ProxyAdmin.upgrade.selector,
          ITransparentUpgradeableProxy(proxy),
          impl
        ),
        "Base: upgrade ChainlinkOEVMorphoWrapper implementation"
      );
    }

    // Optimism actions
    vm.selectFork(OPTIMISM_FORK_ID);
    {
      address oracle = addresses.getAddress("CHAINLINK_ORACLE");
      address newWrapper = addresses.getAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3"
      );
      _pushAction(
        oracle,
        abi.encodeWithSignature("setFeed(string,address)", "WETH", newWrapper),
        "Optimism: ChainlinkOracle.setFeed(WETH, new OEV wrapper)"
      );
    }
  }

  function validate(Addresses addresses, address) public override {
    // Base
    vm.selectFork(BASE_FORK_ID);
    {
      ChainlinkOracle oracle = ChainlinkOracle(
        addresses.getAddress("CHAINLINK_ORACLE")
      );
      address newWrapper = addresses.getAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3"
      );
      assertEq(
        address(oracle.getFeed("WETH")),
        newWrapper,
        "Base: WETH feed not updated"
      );

      ChainlinkOEVWrapper w = ChainlinkOEVWrapper(payable(newWrapper));
      assertEq(w.liquidatorFeeBps(), LIQUIDATOR_FEE_BPS, "Base: bps");
      assertEq(w.maxRoundDelay(), MAX_ROUND_DELAY, "Base: delay");
      assertEq(w.maxDecrements(), MAX_DECREMENTS, "Base: decrements");
      assertEq(
        w.owner(),
        addresses.getAddress("TEMPORAL_GOVERNOR"),
        "Base: owner"
      );

      // Morpho proxy implementation check
      ChainlinkOEVMorphoWrapper m = ChainlinkOEVMorphoWrapper(
        addresses.getAddress("CHAINLINK_WELL_USD_ORACLE_PROXY")
      );
      assertEq(
        m.liquidatorFeeBps(),
        m.liquidatorFeeBps(),
        "Base: morpho storage sanity"
      );
    }

    // Optimism
    vm.selectFork(OPTIMISM_FORK_ID);
    {
      ChainlinkOracle oracle = ChainlinkOracle(
        addresses.getAddress("CHAINLINK_ORACLE")
      );
      address newWrapper = addresses.getAddress(
        "CHAINLINK_ETH_USD_OEV_WRAPPER_V3"
      );
      assertEq(
        address(oracle.getFeed("WETH")),
        newWrapper,
        "OP: WETH feed not updated"
      );
      ChainlinkOEVWrapper w = ChainlinkOEVWrapper(payable(newWrapper));
      assertEq(w.liquidatorFeeBps(), LIQUIDATOR_FEE_BPS, "OP: bps");
      assertEq(w.maxRoundDelay(), MAX_ROUND_DELAY, "OP: delay");
      assertEq(w.maxDecrements(), MAX_DECREMENTS, "OP: decrements");
    }
  }
}
```

(Address keys used: `CHAINLINK_ETH_USD_FEED`, `CHAINLINK_ORACLE`,
`OEV_PROTOCOL_FEE_REDEEMER`, `TEMPORAL_GOVERNOR`, `MRD_PROXY_ADMIN`,
`CHAINLINK_WELL_USD_ORACLE_PROXY`. If any key name differs — verify against
`chains/8453.json` and `chains/10.json` and adjust. The ProxyAdmin key in
particular varies across deployments; search for "PROXY_ADMIN" in
`chains/8453.json` and pick the one that owns
`CHAINLINK_WELL_USD_ORACLE_PROXY`.)

- [ ] **Step 3: Build**

Run: `forge build` Expected: PASS.

- [ ] **Step 4: Dry-run simulate + validate**

Run:

```bash
source proposals/mips/mip-x53/x53.sh && \
  DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true DO_DEPLOY=true DO_AFTER_DEPLOY=true \
  forge script proposals/mips/mip-x53/mip-x53.sol:mipx53
```

Expected: Deploys on each fork, pushes actions, prints calldata, validates
without revert.

If it reverts, inspect the revert reason and adjust the address keys in the
contract, or adjust the helpers (`ProxyAdmin.upgrade` vs `upgradeAndCall` etc.)
based on what the matching reference MIP in the repo uses.

- [ ] **Step 5: Commit**

```bash
git add proposals/mips/mip-x53/mip-x53.sol
git commit -m "feat(mip-x53): deploy new OEV wrappers + upgrade morpho wrapper"
```

---

## Task 16: Register new addresses in chains/\*.json

**Files:**

- Modify: `chains/8453.json`
- Modify: `chains/10.json`

- [ ] **Step 1: After simulation succeeds, extract the deployed addresses**

The `_printAddressesChanges` output from Task 15 Step 4 prints all new address
additions. Capture them (or copy from the JSON file the proposal writes under
`proposals/mips/mip-x53/mip-x53.sol/mipx53.json`).

- [ ] **Step 2: Base (chains/8453.json)**

Add two entries (deployed addresses from Step 1). Search for the existing
`CHAINLINK_ETH_USD_OEV_WRAPPER` entry (line ~1355) and:

1. Change its `name` to `CHAINLINK_ETH_USD_OEV_WRAPPER_DEPRECATED_V3` (keeping
   the address/other fields).
2. Add a new entry with `name: CHAINLINK_ETH_USD_OEV_WRAPPER` pointing at the
   new deployment.
3. Add `CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2` entry for the new Morpho
   wrapper implementation.

Example new Core wrapper entry shape (match exact format of neighbors):

```json
{
  "addr": "0xNEW_ADDRESS",
  "isContract": true,
  "name": "CHAINLINK_ETH_USD_OEV_WRAPPER"
}
```

- [ ] **Step 3: Optimism (chains/10.json)**

Same rename pattern for the existing `CHAINLINK_ETH_USD_OEV_WRAPPER` (line ~760)
and add the new deployed address.

- [ ] **Step 4: Re-run simulate to confirm addresses resolve**

Run:

```bash
source proposals/mips/mip-x53/x53.sh && \
  DO_VALIDATE=true DO_BUILD=true DO_RUN=true \
  forge script proposals/mips/mip-x53/mip-x53.sol:mipx53
```

Expected: PASS (no `address already set` collisions; proposal runs clean against
the registered addresses).

- [ ] **Step 5: Commit**

```bash
git add chains/8453.json chains/10.json
git commit -m "chore(addresses): register MIP-X53 deployments; deprecate prior wrappers"
```

---

## Task 17: Final guard rails

- [ ] **Step 1: Full unit suite**

Run: `make test-unit` Expected: PASS.

- [ ] **Step 2: Full integration suite on Base**

Run: `PRIMARY_FORK_ID=8453 forge test --match-path "test/integration/**" -vvv`
Expected: PASS (long-running; feel free to scope further if CI covers this).

- [ ] **Step 3: Full integration suite on Optimism**

Run:
`PRIMARY_FORK_ID=10 forge test --match-path "test/integration/oracle/*" -vvv`
Expected: PASS.

- [ ] **Step 4: CI profile smoke**

Run: `FOUNDRY_PROFILE=ci forge test --match-path "test/unit/**"` Expected: PASS.

- [ ] **Step 5: Slither**

Run: `make slither` Expected: No new findings on
`src/oracles/ChainlinkOEVWrapper.sol`,
`src/oracles/ChainlinkOEVMorphoWrapper.sol`, or
`src/oracles/IOEVWrapperFeed.sol` beyond baseline.

- [ ] **Step 6: Prettier + solhint**

Run: `npm run prettier && npm run lint` Expected: Clean.

- [ ] **Step 7: Push and open PR**

```bash
git push -u origin feat/chainlink-oev-fix
gh pr create --title "fix(oev): dereference wrapped loan feed + morpho validation parity (MIP-X53)" --body "$(cat <<'EOF'
## Summary
- Fix loan-vs-collateral price desync in `ChainlinkOEVWrapper` and `ChainlinkOEVMorphoWrapper`.
- Restore `_validateRoundData` parity on the Morpho wrapper's loan-price path.
- MIP-X53 redeploys the Core wrapper on Base/OP and upgrades the Morpho wrapper proxy on Base.
- Addresses bounty submission code-423n4/moonwell-bug-bounty-submissions#150 (sponsor-acknowledged Medium, goodwill bounty).

## Test plan
- [ ] `make test-unit` green locally
- [ ] `PRIMARY_FORK_ID=8453 forge test --match-path "test/integration/oracle/*"` green
- [ ] `PRIMARY_FORK_ID=10 forge test --match-path "test/integration/oracle/*"` green
- [ ] Deref regression tests fail on `main` and pass on this branch
- [ ] MIP-X53 `simulate` + `validate` pass on Base and Optimism forks
- [ ] Slither: no new findings
EOF
)"
```

---

## Self-Review

Running the checklist against the spec.

**1. Spec coverage:**

| Spec §           | Task(s)                                  |
| ---------------- | ---------------------------------------- |
| §2 scope item 1  | Tasks 3–7 (Core wrapper desync fix)      |
| §2 scope item 2  | Tasks 8–10 (Morpho wrapper desync fix)   |
| §2 scope item 3  | Task 9 + Task 10 validation-parity tests |
| §2 scope item 4  | Tasks 3, 5–7, 8, 10, 11, 12              |
| §2 scope item 5  | Tasks 14, 15                             |
| §2 scope item 6  | Task 16                                  |
| §3.1 interface   | Task 1                                   |
| §3.2 helper      | Tasks 4, 9                               |
| §3.3 no storage  | Enforced by §15 "no reinitializer" note  |
| §4.1 Core code   | Task 4                                   |
| §4.2 Morpho code | Task 9                                   |
| §5.1 unit tests  | Tasks 3, 5, 6, 7, 8, 10                  |
| §5.2 integration | Tasks 11, 12                             |
| §6 MIP           | Tasks 14, 15, 16                         |
| §9 acceptance    | Task 13 (pre-MIP), Task 17 (post-MIP)    |

All spec sections covered.

**2. Placeholders:**

None. Every step has concrete code or a concrete command. The few conditional
notes (e.g. "verify the exact `ProxyAdmin` key against `chains/8453.json`") are
guardrails, not TBDs — the engineer has both the address-key name they should
try first and the fallback step.

**3. Type/name consistency:**

- `_resolveRawFeed(AggregatorV3Interface)` — same signature in Tasks 1, 4, 9,
  and all test callers.
- `IOEVWrapperFeed.priceFeed()` — same in Tasks 1, 4, 9, 11, 12.
- Deployed-wrapper address key: `CHAINLINK_ETH_USD_OEV_WRAPPER_V3` in Tasks 15
  and 16. Old entry gets renamed to
  `CHAINLINK_ETH_USD_OEV_WRAPPER_DEPRECATED_V3`, then the new one takes the
  canonical name `CHAINLINK_ETH_USD_OEV_WRAPPER` (Task 16 Step 2-3). This is
  intentional — deploy time uses the V3 suffix to avoid clashing with the
  still-registered canonical address, and the canonical name flips to the new
  deployment after governance execution is simulated.
- Morpho impl key: `CHAINLINK_WELL_USD_ORACLE_PROXY_IMPL_V2` in Tasks 15, 16.
  Consistent.
- Harness exposer names: `exposed_getLoanTokenPrice`, `exposed_resolveRawFeed` —
  consistent across Tasks 3, 8, and the contracts in the harness.

No drift.

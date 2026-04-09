# PR #560 Review Findings — `[WIP] mainnet deployment proposal`

**Branch:** `deploy/mainnet` -> `feat/multichain-gov-refactor` **Review Date:**
2026-04-09 (round 1), 2026-04-09 (round 2) **Reviewers:** Code Reviewer Agent,
Security Auditor Agent

---

## Critical Findings

### C-4: `toForkId()` not updated for Ethereum chain ID

- **File:** `src/utils/ChainIds.sol:108-122`
- **Issue:** `toForkId(ETHEREUM_CHAIN_ID)` reverts with "invalid chain id". This
  breaks governance simulation for any Ethereum-targeted proposal.
  `HybridProposalV2.getTemporalGovPayloadByChain()` calls this.
- **Fix:** Add
  `else if (chainId == ETHEREUM_CHAIN_ID || chainId == ETHEREUM_SEPOLIA_CHAIN_ID) { return ETHEREUM_FORK_ID; }`.
- [ ] Fixed

---

## High Findings

### H-5: WstETHExchangeRateAdapter — staleness limitation

- **File:** `src/oracles/WstETHExchangeRateAdapter.sol:98-119`
- **Issue:** `updatedAt = block.timestamp` is fabricated — if wstETH contract is
  paused/exploited, price appears fresh when stale. int256 overflow guard was
  added (round 1), but staleness remains an inherent limitation.
- **Fix:** Consider monitoring Lido oracle update frequency externally, or
  adding a `maxStaleness` parameter. At minimum, document the limitation in risk
  params.
- [x] int256 overflow guard fixed
- [ ] Staleness monitoring/documentation

### H-NEW-1: `PAUSE_GUARDIAN == BREAK_GLASS_GUARDIAN` on Ethereum

- **File:** `chains/1.json`
- **Issue:** Both resolve to `0x5B710010586C1b728B047c3E42473c700eeA4026`. Using
  break glass permanently disables the pause guardian (burns to `address(0)`).
  Collapses two distinct security roles into one key.
- **Fix:** Assign `BREAK_GLASS_GUARDIAN` a distinct multisig (e.g.,
  `SECURITY_COUNCIL` at `0x446342AF4F3bCD374276891C6bb3411bf2F8779E` is already
  in `chains/1.json`).
- [ ] Fixed

### H-NEW-2: `mip-e00.initProposal()` re-runs `x52.afterDeploy()` unconditionally

- **File:** `proposals/mips/mip-e00/mip-e00.sol:62-76`
- **Issue:** If x52 is already deployed and initialized on mainnet, calling
  `initialize()` again reverts with "Initializable: contract is already
  initialized". Breaks simulation/dry-run of mip-e00 against a post-x52 fork.
- **Fix:** Add idempotency guard — skip `x52.afterDeploy()` if governor is
  already initialized.
- [ ] Fixed

### H-NEW-3: Initial mint token balances unverified

- **File:** `proposals/mips/mip-e00/mip-e00.sol:826-855`
- **Issue:** `build()` pushes `approve`+`mint` actions on behalf of the governor
  proxy for WETH, USDC, USDT, cbBTC, weETH, wstETH. No on-chain check that the
  governor actually holds these tokens before execution.
- **Fix:** Add `validate()` check for
  `governor.balanceOf(underlying) >= initialMintAmount` per market, or document
  funding requirement in deployment runbook.
- [ ] Fixed

---

## Medium Findings

### M-1: `_pushAction` fork ID inference is fragile

- **File:** `proposals/proposalTypes/HybridProposalV2.sol`
- **Issue:** Fixed in `_pushAction` (now uses `_forkIdToActionType()`), but
  `getTemporalGovPayloadByChain()` still uses raw `ActionType(forkId)` cast.
  Same ordinal coupling — fix was applied inconsistently.
- **Fix:** Replace `ActionType(forkId)` with `_forkIdToActionType(forkId)` in
  `getTemporalGovPayloadByChain()`.
- [x] `_pushAction` fixed
- [ ] `getTemporalGovPayloadByChain` still uses raw cast

### M-2: Wrong proposalType in mips.json for mip-e00

- [x] Fixed — changed to `"HybridProposalV2"`

### M-3: mip-e00 reads mTokens.json as proposal description

- [x] Fixed — now reads `MIP-E00.md`

### M-5: foundry.toml production settings

- **File:** `foundry.toml`
- **Issue:** `revert_strings = "debug"` increases bytecode size/gas.
  `sparse_mode = true` may skip security-relevant compilations.
- **Fix:** Disable both for production builds.
- [ ] Fixed

### M-NEW-2: cbBTC priced at BTC/USD directly — assumes 1:1 peg

- **File:** `proposals/mips/mip-e00/mTokens.json`, `chains/1.json`
- **Issue:** cbBTC (Coinbase Wrapped Bitcoin) uses `CHAINLINK_BTC_USD` directly.
  No cbBTC/BTC rate applied. Depeg event enables under-collateralized borrowing.
  Bounded by 75% CF and 500 borrow cap.
- **Fix:** Document the peg assumption explicitly. Consider a capped oracle.
- [ ] Acknowledged / Fixed

### M-NEW-3: `checkEthereumActions` lacks Wormhole Core exclusion

- **File:** `proposals/utils/ProposalChecker.sol:114-138`
- **Issue:** Unlike the Moonbeam checker, doesn't prevent proposals from
  accidentally calling `WORMHOLE_CORE` as an Ethereum action target.
- **Fix:** Add check that no target equals `WORMHOLE_CORE` on Ethereum.
- [ ] Fixed

---

## Low / Informational

- [ ] `chainForkToName(3)` reverts — no Ethereum case in
      `src/utils/ChainIds.sol:320-332`
- [ ] `getRoundData` ignores `roundId` parameter in
      `WstETHExchangeRateAdapter.sol` (always returns latest)
- [ ] Duplicate oracle address entries in `chains/1.json` (e.g.
      `CHAINLINK_ETH_USD` / `ETH_ORACLE`)
- [ ] Missing SPDX license in
      `test/integration/oracle/WstETHExchangeRateAdapterIntegration.t.sol`
- [ ] Hardcoded `nonce = 2` in `mip-e00.sol` without documentation
- [ ] `PAUSE_GUARDIAN` resolution in `mip-e00.sol:543-544` missing explicit
      chain context qualifier
- [ ] Stale "MIP-X41" comments in `mip-e00.sol` (lines 25, 82, 83, 478, 638) —
      should reference MIP-X52
- [ ] No test coverage for `executeBreakGlass` functionality
- [ ] `tasks/test-coverage-audit.md` committed to repo (should be in project
      management tooling)

# PR #560 Review Findings — `[WIP] mainnet deployment proposal`

**Branch:** `deploy/mainnet` -> `feat/multichain-gov-refactor` **Review Date:**
2026-04-09 **Reviewers:** Code Reviewer Agent, Security Auditor Agent

---

## Critical Findings

### C-1: MultichainGovernorV2 proxy deployed uninitialized — front-run window

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1364-1378` (deploy),
  `:1717-1804` (afterDeploy)
- **Issue:** `deploy()` creates `TransparentUpgradeableProxy` with empty `""`
  init data. `afterDeploy()` calls `initialize()` in a **separate transaction**.
  An attacker can front-run to initialize with malicious params (their own
  pauseGuardian, breakGlassGuardian, trusted senders, votingPower contract).
- **Fix:** Encode the `initialize()` call directly as the `data` parameter in
  the `TransparentUpgradeableProxy` constructor to make deployment atomic.
- [ ] Fixed

### C-2: Moonbeam TemporalGovernor behind proxy is broken

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1447-1471`
- **Issue:** `TemporalGovernor` is NOT an upgradeable contract. It sets
  `trustedSenders`, `wormholeBridge`, `proposalDelay`,
  `permissionlessUnpauseTime`, and `owner` in its **constructor** — these
  populate the **implementation's** storage, not the proxy's. The proxy will
  have zero trusted senders and incorrect ownership, bricking Moonbeam
  governance entirely.
- **Note:** On Base, `TemporalGovernor` was deployed WITHOUT a proxy — that is
  the correct pattern.
- **Fix:** Either deploy without proxy (matching Base pattern) or redesign as
  upgradeable with a proper `initialize()`.
- [ ] Fixed

### C-3: Missing addresses in `chains/1.json` — PAUSE_GUARDIAN_MULTISIG and BREAK_GLASS_GUARDIAN

- **File:** `chains/1.json`, referenced from `mip-x41.sol:1734-1738`
- **Issue:** `afterDeploy` on Ethereum calls
  `addresses.getAddress("PAUSE_GUARDIAN_MULTISIG")` and
  `addresses.getAddress("BREAK_GLASS_GUARDIAN")`, but neither exists for chain
  ID 1. Only `PAUSE_GUARDIAN` exists. Runtime revert during deployment.
- **Fix:** Add both addresses to `chains/1.json` for Ethereum.
- [ ] Fixed

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

### H-1: Wrong proxy admin for VotingPowerAggregator on Base/Optimism

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1586, 1647`
- **Issue:** Uses `MRD_PROXY_ADMIN` (Multi Reward Distributor's proxy admin)
  marked `// TODO: correct?`. This means the MRD admin can upgrade governance
  voting power contracts — violates principle of least privilege.
- **Fix:** Use the correct dedicated `PROXY_ADMIN` for VotingPowerAggregator.
- [ ] Fixed

### H-2: Whitelisted calldatas left empty (active TODO)

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1793`
- **Issue:** `// TODO: determine whitelisted calldatas` — governor initializes
  with zero emergency functions. No break-glass operations available at launch.
- **Fix:** Determine and configure all required whitelisted calldatas before
  deployment.
- [ ] Fixed

### H-3: Single-step ownership transfer of 75 Moonbeam contracts to potentially broken proxy

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1961-1989`
- **Issue:** `transferOwnership(temporalGovernor)` is a single-step transfer (no
  `acceptOwnership` confirmation). Combined with C-2, ownership is transferred
  to a non-functional contract, permanently locking Moonbeam governance.
- **Fix:** Verify TemporalGovernor is functional before transfers. Consider
  `Ownable2Step` or making ownership transfer a separate proposal.
- [ ] Fixed

### H-4: No storage layout validation for MultichainGovernor upgrade on Moonbeam

- **File:** `proposals/mips/mip-x41/mip-x41.sol:1819-1821`, `foundry.toml`
- **Issue:** `build_info = true` and `extra_output = ["storageLayout"]` are
  disabled. No storage layout check before upgrading the MultichainGovernor.
  Could silently corrupt governance state.
- **Fix:** Enable storage layout output and run OpenZeppelin Upgrades storage
  layout validation.
- [ ] Fixed

### H-5: WstETHExchangeRateAdapter — no staleness check + unchecked int256 cast

- **File:** `src/oracles/WstETHExchangeRateAdapter.sol:98-119`
- **Issues:**
  - `updatedAt = block.timestamp` is fabricated — if wstETH contract is
    paused/exploited, price appears fresh when stale.
  - `int256(rate)` cast is unchecked — overflow at `type(int256).max` would
    return negative, bricking the price feed.
- **Fix:** Add `require(rate <= uint256(type(int256).max))` and document
  staleness limitations.
- [ ] Fixed

---

## Medium Findings

### M-1: `_pushAction` fork ID inference is fragile

- **File:** `proposals/proposalTypes/HybridProposalV2.sol:3084-3087`
- **Issue:** `require(fork <= 3)` + `ActionType(fork)` relies on fork creation
  order exactly matching the `ActionType` enum (Moonbeam=0, Base=1, Optimism=2,
  Ethereum=3). If forks are created in a different order, actions are silently
  mislabeled.
- **Fix:** Use an explicit mapping from fork ID to ActionType.
- [ ] Fixed

### M-2: Wrong proposalType in mips.json for mip-e00

- **File:** `proposals/mips/mips.json`
- **Issue:** `mip-e00` inherits `HybridProposalV2` but is registered as
  `"proposalType": "HybridProposal"`.
- **Fix:** Change to `"HybridProposalV2"` or verify tooling treats them
  equivalently.
- [ ] Fixed

### M-3: mip-e00 reads mTokens.json as proposal description

- **File:** `proposals/mips/mip-e00/mip-e00.sol:434-448`
- **Issue:** Proposal description is set to raw JSON content of `mTokens.json`
  instead of a human-readable description file.
- **Fix:** Read `MIP-E00.md` or a proper description file instead.
- [ ] Fixed

### M-4: No validation that old Moonbeam governor is decommissioned

- **File:** `proposals/mips/mip-x41/mip-x41.sol` — `validate()` section
- **Issue:** Old Moonbeam MultichainGovernor remains deployed and upgraded.
  Could still be used as a fallback governance path if someone with sufficient
  WELL votes proposes through it.
- **Fix:** Add validation that old governor cannot initiate new proposals.
- [ ] Fixed

### M-5: foundry.toml production settings

- **File:** `foundry.toml`
- **Issue:** `revert_strings = "debug"` increases bytecode size/gas.
  `sparse_mode = true` may skip security-relevant compilations.
- **Fix:** Disable both for production builds.
- [ ] Fixed

---

## Low / Informational

- [ ] `chainForkToName(3)` reverts — no Ethereum case in
      `src/utils/ChainIds.sol:320-332`
- [ ] `getRoundData` ignores `roundId` parameter in
      `WstETHExchangeRateAdapter.sol` (always returns latest)
- [ ] Duplicate oracle address entries in `chains/1.json` (e.g.
      `CHAINLINK_ETH_USD` / `ETH_ORACLE`)
- [ ] `tasks/test-coverage-audit.md` committed to repo (should be in project
      management tooling)
- [ ] Missing SPDX license in
      `test/integration/oracle/WstETHExchangeRateAdapterIntegration.t.sol`
- [ ] Hardcoded `nonce = 2` in `mip-e00.sol:446` without coordination
- [ ] Missing `x41.md` description file (referenced at `mip-x41.sol:1293` but
      not in diff)
- [ ] `PAUSE_GUARDIAN` resolution in `mip-e00.sol:543-544` missing explicit
      chain context qualifier
- [ ] MIP-E00 mToken market init requires governor to hold real token balances
      on mainnet

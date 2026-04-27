# Proposal Rules

- Always set `id: 0` in `proposals/mips/mips.json` when creating new proposals
- Naming: `mip-b##` (Base), `mip-x##` (Ethereum/cross-chain), `mip-m##`
  (Moonbeam), `mip-o##` (Optimism)
- Each proposal folder needs: `.sh`, `.json`, `.md` files
- Shell scripts set: `JSON_PATH`, `DESCRIPTION_PATH`, `PRIMARY_FORK_ID`
- Use templates from `proposals/templates/` when applicable (MarketAdd,
  MarketUpdate, RewardsDistribution)
- Proposal lifecycle: `deploy()` → `afterDeploy()` → `build()` → `simulate()` →
  `validate()`
- Load all addresses from `proposals/Addresses.sol` or `chains/*.json` — never
  hardcode
- Duration calculations: always show math explicitly for user verification
- To run a proposal simulation:
  `source proposals/mips/mip-xxx/xxx.sh && DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=false forge script proposals/templates/Template.sol`
- For rewards-distribution MIPs (template-only or subclass), run
  `make audit-rewards PROPOSAL=mip-xNN` before opening the PR. This verifies
  worker-generated numbers balance across chains (TG flow conservation, MRD
  budget = Σ speeds × duration, safety-module budget = stkEPS × duration,
  Moonbeam bridge fan-out, no negative amounts, 4-week epoch). Deterministic,
  ~1s, no LLM. The same check runs in CI via `proposal-summary.yml`.
- Add the `mips.json` entry only AFTER the corresponding `.sol` file exists —
  registering an entry whose artifact doesn't exist breaks every
  `PostProposalCheck` test via `vm.getCode` failure during setUp
- Address registration in `chains/*.json` happens POST on-chain execution, not
  pre — registering placeholder dry-run addresses breaks simulate because
  `_checkAddress` validates `code.length > 0` at fork state
- Use `afterDeploy()` (which runs before `build()`) to snapshot pre-upgrade
  state into proposal instance vars, so `validate()` can assert strict equality
  after governance executes (catches accidental storage resets)
- For Morpho oracle wrapper proxies, the ProxyAdmin is
  `CHAINLINK_ORACLE_PROXY_ADMIN` (not `MRD_PROXY_ADMIN` — that one is for mToken
  markets)

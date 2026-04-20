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
- `_reduceReserves`, `_setPendingAdmin`, and most MToken admin functions return
  error codes silently — they do NOT revert. Always verify a successful
  reduction took effect before chaining dependent actions (e.g. `approve` +
  `repayBorrowBehalf` after `_reduceReserves`)
- To inherit a template (e.g. `RewardsDistributionTemplate`), its
  `build`/`validate`/`beforeSimulationHook`/`name` must be declared `virtual` —
  add if missing
- `id: 0` in `mips.json` marks an in-development proposal; `PostProposalCheck`
  simulates it in ~12 integration tests, so malformed JSON here breaks the whole
  test matrix
- Monthly rewards JSON/MD come from
  `https://moonwell-reward-automation.moonwell.workers.dev/?type=json|markdown&timestamp=<unix>`.
  Always sanity-check output for negative amounts (especially `withdrawWell`)
  and `nativeValue: 0` fields that break simulation
- Before adding `deal(...)` in `beforeSimulationHook` or a proposal, compare
  against real on-chain state (`cast call <market> "totalReserves()(uint256)"` /
  `"getCash()(uint256)"`). Never let a mock reduce a mainnet balance

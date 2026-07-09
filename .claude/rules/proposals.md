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
- `repayBorrowBehalf(uint256.max)` clips to `accountBorrows` (sentinel at
  `src/MToken.sol:1297`). Use it only for FULL repays where you've already
  funded the market to cover the entire debt. For PARTIAL repays sized by
  reserve availability (e.g. bad-debt recovery), use the literal amount — the
  sentinel will clip to the full debt and then revert on insufficient allowance
  in `doTransferIn`
- Cross-chain xWELL bridging (`xWELLRouter.bridgeToRecipient`) on V3+
  `WormholeBridgeAdapter` uses `publishMessage`/`processVAA`, not the deprecated
  relayer path the template's `WormholeRelayerAdapter` mocks. Rewards MIPs that
  bridge must pre-fund destination `TEMPORAL_GOVERNOR` balances in
  `beforeSimulationHook` or bridged WELL never arrives in fork simulation
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
- Two OEV wrapper types with different upgrade patterns: `*_OEV_WRAPPER` keys
  are non-upgradeable `ChainlinkOEVWrapper` (Core mToken markets) — to upgrade,
  redeploy + rewire via `setFeed`. `*_ORACLE_PROXY` keys are upgradeable
  `ChainlinkOEVMorphoWrapper` (Morpho-Blue) — upgrade impl behind the proxy via
  `ProxyAdmin.upgrade`.
- For wrapper redeploys, follow MIP-X43's archive-then-promote pattern:
  `addAddress("<name>_OEV_WRAPPER_DEPRECATED_VN", oldAddr)` then
  `changeAddress("<name>_OEV_WRAPPER", newAddr, true)` to atomically swap the
  canonical name. MIRROR live wrapper params via getters (`liquidatorFeeBps`,
  `maxRoundDelay`, `maxDecrements`, `feeRecipient`, `owner`, `priceFeed`) rather
  than hardcoding — found 4000→3000 bps drift between MIP-X38 era and MIP-X43
  era when hardcoding.
- Moonbeam enforces a per-transaction gas cap of **16,777,216 (2^24)**. A
  `propose()` tx above that is silently dropped by every RPC frontend we've
  tested (Goldsky returns a hash but never propagates; Alchemy and the public
  Moonbeam RPC reject at submit with "exceeds transaction gas limit cap"). If
  `cast estimate` on a rewards MIP's `propose()` returns > ~15M gas, split the
  proposal along chain-destination lines (e.g. x51a = Moonbeam+Optimism, x51b =
  Base rewards, x51c = Base bad-debt) and regenerate the `.json` for each half
  from the worker output.
- When splitting a rewards MIP, the Moonbeam `bridgeToRecipient` for each
  destination must cover that split's **first** Base/Optimism TG outflow in
  `_buildExternalChainActions` order — not the net TG balance. Build order is
  fixed:
  `transferFrom → setRewardSpeeds → withdrawWell → transferReserves → multiRewarder → merkleCampaigns`.
  Because `transferFrom(TG→MRD)` runs before `withdrawWell` brings WELL back
  into TG, a bridge sized only for the net balance will revert on the first
  transfer with `ERC20: transfer amount exceeds balance`. Trace TG
  inflow/outflow step-by-step when rebalancing bridge amounts across split MIPs.
- `RewardsDistributionV2Template` (Ethereum-hub rewards, the current template)
  auto-batches a large epoch: `chunkCount`/`chunkActions` split an oversized
  per-chain wormhole bundle across multiple VAAs, and `batchProposeSplits`
  submits the proposal in several init+append `propose()` calls, all sized from
  the encoded calldata. A new rewards MIP does NOT need to hand-tune chunk
  boundaries the way MIP-X59 did (`BASE_CHUNK_BOUNDARY`, manual `chunkCount`
  overrides) — inherit the template and it computes a submittable split. Only
  override the `virtual` budgets `maxChunkPayloadBytes()` (default 11KB, per-VAA
  gov-action payload) / `maxProposeCallBytes()` (default 12KB, per-`propose()`
  call — gas-bound, not a protocol cap) if a chain's gas ceiling differs. The
  chunker never splits a dependent group (reduce→transfer reserve pair,
  multiRewarder approve→notify, merkle approve→accept→create) across VAAs; new
  dependent action sequences must call `_markAtomicGroup` in build so the
  chunker keeps them in one VAA.

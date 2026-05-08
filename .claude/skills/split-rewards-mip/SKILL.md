---
name: split-rewards-mip
description:
  Split a rewards-distribution MIP that exceeds Moonbeam's 16,777,216 (2^24)
  per-tx gas cap into chain-destination chunks (e.g. x51 → x51a/x51b/x51c).
  Walks through the cast estimate precheck, generates new folders/JSON/SH/SOL,
  and rebalances the bridgeToRecipient amounts in TG-flow order so each split's
  first outflow is fully funded.
---

# Split Rewards MIP

Use when a rewards-distribution MIP's `propose()` gas estimate exceeds ~15M
(Moonbeam's per-tx cap is 16,777,216). Above that, the tx is silently dropped by
Goldsky/Alchemy/public RPC, or rejected at submit on Alchemy/public Moonbeam
RPC.

## Inputs

- The original MIP folder name (e.g. `mip-x51`).
- Suggested split scheme — usually by destination chain. Example for x51:
  - `x51a` = Moonbeam-only payload + Optimism rewards bridge
  - `x51b` = Base rewards bridge
  - `x51c` = Base bad-debt repayment

## Workflow

### 1. Pre-check the gas estimate

```bash
cast estimate <governor-address> "propose(...)" --rpc-url $MOONBEAM_RPC_URL
```

If this returns > ~15M, splitting is required. If it's between 14M and 16M,
recommend splitting anyway — Moonbeam block-cap headroom is unforgiving.

### 2. Plan the split

Decide chain-destination boundaries. The build order in
`_buildExternalChainActions` is **fixed** and cannot be reordered:

```
transferFrom → setRewardSpeeds → withdrawWell → transferReserves → multiRewarder → merkleCampaigns
```

For each split, identify which actions move into it. Each split's Moonbeam
payload runs independently as a separate `propose()`.

### 3. Rebalance the bridge amounts

Critical math: `bridgeToRecipient` for each destination chain in each split must
cover that split's **FIRST** Base/Optimism `TEMPORAL_GOVERNOR` outflow — NOT the
net TG balance after all actions.

Why: `transferFrom(TG → MRD)` runs BEFORE `withdrawWell` brings WELL back into
TG. A bridge sized only for the net balance will revert on the first transfer
with `ERC20: transfer amount exceeds balance`.

Trace TG inflow/outflow step-by-step. Show the math explicitly to the user for
verification.

### 4. Generate new folders

For each split (e.g. `x51a`, `x51b`, `x51c`):

- `proposals/mips/mip-x51<letter>/x51<letter>.sh`
- `proposals/mips/mip-x51<letter>/x51<letter>.json`
- `proposals/mips/mip-x51<letter>/x51<letter>.md`
- `proposals/mips/mip-x51<letter>/mip-x51<letter>.sol` (if standalone — copies
  the parent)

Mark every `.sh` executable in git:
`git update-index --chmod=+x proposals/mips/mip-x51<letter>/x51<letter>.sh`.

### 5. Regenerate the JSON for each split

Pull from the rewards automation worker:

```
https://moonwell-reward-automation.moonwell.workers.dev/?type=json&timestamp=<unix>
```

Filter the worker output to the actions that belong to this split. Sanity-check:
no negative `withdrawWell`, no `nativeValue: 0`.

### 6. Update mips.json

Add an entry per split with `id: 0` (in-development sentinel). Path points to
the artifact:

```json
{
  "envpath": "proposals/mips/mip-x51a/x51a.sh",
  "governor": "MultichainGovernor",
  "id": 0,
  "path": "mip-x51a.sol/mipx51a.json",
  "proposalType": "HybridProposal"
}
```

Keep the array sorted with `id: 0` entries at the top, then descending by id.

### 7. Re-run gas estimate per split

After splitting, run `cast estimate` on each split's `propose()` to confirm all
are below 15M. If any one is still over, sub-split it further.

### 8. Verify with audit-rewards

Run `make audit-rewards PROPOSAL=mip-x51a` (and b, c) on each split. The audit
runs in CI via `proposal-summary.yml` and verifies:

- TG flow conservation
- MRD budget = Σ speeds × duration
- Safety-module budget = stkEPS × duration
- Moonbeam bridge fan-out
- 4-week epoch
- No negative amounts

### 9. Simulate each split

Use the `/simulate-mip` skill once per split.

## Common pitfalls

- **Net-balance bridge sizing**: see step 3 above. Always size to the first
  outflow.
- **Forgot exec bit**: `forge test --ffi` will fail with `Permission denied` on
  the new `.sh` files. Always `git update-index --chmod=+x`.
- **Stale cached IDs in `mips.json`**: keep `id: 0` until the proposal lands
  on-chain. Reviewers will catch real IDs in unmerged PRs.
- **Double-counting bridged WELL**: when one split bridges WELL that the next
  split assumes already arrived in TG, fork sims will pass but on-chain ordering
  matters. Document the sequencing in each split's `.md`.

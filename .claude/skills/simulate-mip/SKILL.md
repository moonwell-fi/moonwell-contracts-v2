---
name: simulate-mip
description:
  Run a Moonwell governance proposal simulation against the canonical fork
  command (DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=false forge
  script ... --ffi). Pass the MIP folder name as the argument (e.g.
  /simulate-mip mip-x51a). Verifies the .sh is executable, sources it, picks the
  right template, and runs the sim with FOUNDRY_PROFILE=ci.
disable-model-invocation: true
---

# Simulate MIP

User-only skill that runs a proposal simulation with the canonical command from
`.claude/rules/proposals.md`.

## Argument

Single argument: the MIP folder name (e.g. `mip-x51a`, `mip-b59`).

If no argument is provided, list every entry in `proposals/mips/mips.json` with
`id: 0` (in-development proposals) and ask which one to simulate.

## Steps

### 1. Resolve paths

- Folder: `proposals/mips/<arg>/`
- Shell script: `proposals/mips/<arg>/<chain-letter><number>.sh` (e.g.
  `x51a.sh`)
- If the folder doesn't exist, list folders under `proposals/mips/` that start
  with the same prefix and ask the user to pick.

### 2. Verify shell-script exec bit

```bash
test -x "<script-path>" || (echo "marking executable for ffi"; chmod +x "<script-path>" && git update-index --chmod=+x "<script-path>")
```

### 3. Pick the template

Read the `.sh` to find `FOUNDRY_SCRIPT` or check `mips.json` for the `path`
field — the artifact name maps to a template under `proposals/templates/`.
Common cases:

- `RewardsDistributionTemplate.sol` →
  `proposals/templates/RewardsDistribution.sol`
- `MarketUpdateTemplate.sol` → `proposals/templates/MarketUpdate.sol`
- `MarketAddV3.sol` → `proposals/templates/MarketAddV3.sol`
- standalone (e.g. `mip-x51a.sol`) → `proposals/mips/<arg>/<arg>.sol`

### 4. Run the sim

```bash
source proposals/mips/<arg>/<script>.sh \
  && DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=false \
     FOUNDRY_PROFILE=ci \
     forge script <template-path> --ffi -vvv 2>&1 | tail -100
```

If the run fails in `setUp()` with a cross-chain error (`WormholeBridge: ...`,
`Initializable: ...`), suggest invoking the `cross-chain-impact-analyzer` agent.

### 5. Surface validate() output

Echo the last `validate()` block — this is what reviewers care about.

## Notes

- Always pass `--ffi`. Proposal `.sh` files are sourced via `vm.ffi`; without it
  the run reverts on `Permission denied`.
- Always use `FOUNDRY_PROFILE=ci` — matches what GitHub Actions runs (1000 fuzz
  runs, deterministic).
- `-vvvv` shows full traces including `console.log` from inside `setUp()`;
  default to `-vvv` and offer to bump to `-vvvv` on failure.
- After in-file renames (functions or vars), prepend `forge build --force` —
  incremental builds can serve stale bytecode and mask compile errors.
- For rewards MIPs, also offer to run `make audit-rewards PROPOSAL=<arg>`
  separately — the sim doesn't catch worker-output bugs.

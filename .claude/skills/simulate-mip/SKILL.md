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
- Shell script: `proposals/mips/<arg>/<basename>.sh`, where `<basename>` is the
  folder name with the `mip-` prefix stripped (e.g. `mip-b59` → `b59.sh`,
  `mip-x47` → `x47.sh`, `mip-x51a` → `x51a.sh`). Suffix letters are preserved
  verbatim.
- If the folder doesn't exist, list folders under `proposals/mips/` that start
  with the same prefix and ask the user to pick.
- If the proposal has no `.sh` (its `mips.json` `envpath` is `""` — e.g.
  `mip-x52/` only carries `.sol` + `.md`), skip the source step in §4 and run
  the standalone simulation directly via the artifact path from `mips.json`.

### 2. Verify shell-script exec bit

```bash
test -x "<script-path>" || (echo "marking executable for ffi"; chmod +x "<script-path>" && git update-index --chmod=+x "<script-path>")
```

### 3. Pick the template

Read the `.sh` to find `FOUNDRY_SCRIPT` or check `mips.json` for the `path`
field — the artifact name maps to a template under `proposals/templates/`.
Common cases:

- `RewardsDistribution.sol/RewardsDistributionTemplate.json` →
  `proposals/templates/RewardsDistribution.sol` (contract
  `RewardsDistributionTemplate`)
- `MarketUpdate.sol/MarketUpdateTemplate.json` →
  `proposals/templates/MarketUpdate.sol` (contract `MarketUpdateTemplate`)
- `MarketAddV3.sol/MarketAddV3.json` → `proposals/templates/MarketAddV3.sol`
- standalone (e.g. `mip-x51a.sol/mipx51a.json`) →
  `proposals/mips/<arg>/<basename>.sol` (where `<basename>` is the folder name
  without the `mip-` prefix)

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

- Always pass `--ffi`. `PostProposalCheck` invokes `vm.ffi` during `setUp` —
  without it the run reverts with an `FFI is disabled` error. (Distinct from
  `Permission denied`, which means the `.sh` itself is not executable; fix with
  `chmod +x` per §2.)
- Always use `FOUNDRY_PROFILE=ci` — matches what GitHub Actions runs (1000 fuzz
  runs, deterministic).
- `-vvvv` shows full traces including `console.log` from inside `setUp()`;
  default to `-vvv` and offer to bump to `-vvvv` on failure.
- After in-file renames (functions or vars), prepend `forge build --force` —
  incremental builds can serve stale bytecode and mask compile errors.
- For rewards MIPs, also offer to run `make audit-rewards PROPOSAL=<arg>`
  separately — the sim doesn't catch worker-output bugs.

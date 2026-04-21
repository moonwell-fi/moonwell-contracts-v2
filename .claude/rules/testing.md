# Testing Rules

- Run `forge build` after every `.sol` edit (enforced by hook)
- Run `forge test` before committing
- Unit tests: `test/unit/*.t.sol`
- Integration tests: `test/integration/`
- Fuzz tests: `test/fuzzing/`
- Formal verification: `test/certora/`
- Use `PRIMARY_FORK_ID=1` for mainnet fork tests (1=Moonbeam, 8453=Base,
  10=Optimism)
- For proposal-specific tests, inherit from `PostProposalCheck`
- CI profile: `FOUNDRY_PROFILE=ci forge test` (1000 fuzz runs)
- Use `forge test --ffi` for any test that runs a proposal — they source `.sh`
  files via `vm.ffi` (fails with `Permission denied` if the script lacks the
  exec bit)
- Make new proposal shell scripts executable in git:
  `git update-index --chmod=+x proposals/mips/mip-xNN/xNN.sh`
- Compiled artifacts live in `artifacts/foundry/` (not `out/`) — see
  `foundry.toml`
- `-vvvv` shows full traces including `console.log` from inside `setUp()`; `-vv`
  often hides them on failures
- After renaming a function/variable that only changes call sites in the same
  file, run `forge build --force` before trusting `forge test` — incremental
  builds can serve stale bytecode and mask compile errors that CI will catch
- In-proposal `validate()` invariants must only couple values that accrue under
  the SAME protocol mechanism. `reservesDown` vs `borrowDown` + other terms
  drift 1-7% across harnesses because `PostProposalCheck` consumers run
  different numbers of vote/queue/execute warps. Prefer directional assertions
  (`assertLt`) and `value ≈ target` checks over `valueA ≈ valueB` equalities
- Prefer `assertEq(allowance, 0)` over `assertLe(allowance, amount)` after a
  matched `approve(market, amount)` / `repayBorrowBehalf(…, amount)` pair — the
  latter is trivially true even if the repay never executed
- After accepting a GitHub-UI / Copilot "cleanup" commit (removes imports,
  renames vars) — verify the file still compiles locally before pushing; the UI
  doesn't see the full symbol graph

# Testing Rules

- Run `forge build` after every `.sol` edit (enforced by hook)
- Run `forge test` before committing
- Unit tests: `test/unit/*.t.sol`
- Integration tests: `test/integration/`
- Fuzz tests: `test/fuzzing/`
- Formal verification: `test/certora/`
- `PRIMARY_FORK_ID` is the foundry FORK INDEX, not a chain ID. Forks are created
  in order in `PostProposalCheck.setUp`: 0=Moonbeam, 1=Base, 2=Optimism,
  3=Ethereum. CI uses `PRIMARY_FORK_ID=1` for Base jobs and `PRIMARY_FORK_ID=2`
  for Optimism jobs (per `.github/workflows/*-integration.yml`).
- `PostProposalCheck.setUp` simulates every MIP with `id:0` in `mips.json`
  before tests run. If a pending MIP mutates registry state (e.g.
  `ChainlinkOracle.setFeed`), tests must resolve via the live registry (e.g.,
  `oracle.getFeed(symbol)`) rather than hardcoded `*_OEV_WRAPPER` address-keys —
  otherwise they break post-simulate.
- For proposal-specific tests, inherit from `PostProposalCheck`
- CI profile: `FOUNDRY_PROFILE=ci forge test` (1000 fuzz runs)
- Integration tests inheriting from `PostProposalCheck` fork all chains in
  `setUp` — Moonbeam RPC flakes (`rpc.moonwell.fi/main/evm/1284` connection
  reset / timeout) are environmental, not test code; retry once before treating
  as a failure
- Run `forge test --ffi` for any integration test using `PostProposalCheck` —
  without it, setUp reverts with `vm.ffi: FFI is disabled`
- After touching any `proposals/mips/mip-x##/*.sol`, run
  `forge build proposals/mips/mip-x##/mip-x##.sol` explicitly — incremental
  builds may not regenerate artifacts that `PostProposalCheck` requires (failure
  mode: `vm.getCode: failed to read from artifacts/foundry/...`)
- `vm.mockCall` etches stub code on the target so unmocked selectors return
  success with empty data; in production `try/catch returns (...)` needs an
  unnamed `catch { }` to swallow the resulting decode panic, and tests must mock
  every selector the SUT might call (e.g. `IOEVWrapperFeed.priceFeed()` in
  addition to `getFeed(string)`)

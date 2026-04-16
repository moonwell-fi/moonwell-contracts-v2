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

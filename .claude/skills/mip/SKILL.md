# Create/Modify MIP Proposal

## Steps

1. Ask user for: MIP number, target chain, reference proposal (if any)
2. Run `git branch --show-current` — refuse to proceed if on `main`
3. Check existing MIP naming pattern: `ls src/proposals/`
4. Load chain addresses from config files (never hardcode addresses)
5. After code changes, run `forge build` to verify compilation
6. Run `forge test --match-contract <MIPName>` to verify tests pass
7. Show diff summary before committing

## Rules

- Storage variables in build() must be initialized from chain config addresses
- Duration calculations: always show math explicitly for user verification
- Follow existing naming convention exactly

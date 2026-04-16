# Moonwell Contracts V2

Cross-chain lending/borrowing protocol deployed on Base, Optimism, Moonbeam, and
Ethereum. Built with Foundry.

## Tech Stack

- **Solidity** (Cancun EVM), **Foundry** (forge, cast, anvil)
- Cross-chain messaging via **Wormhole**
- Safe multisig integration for ops
- OpenZeppelin for proxies, ERC20, utilities

## Project Structure

```
src/                    # Protocol contracts
├── governance/         # MultichainGovernor, TemporalGovernor, Well token
├── oracles/            # Chainlink feeds, composite oracles, OEV wrappers
├── rewards/            # MultiRewardDistributor
├── stkWell/            # Staked WELL token
├── xWELL/              # Cross-chain WELL (Axelar bridge)
├── 4626/               # ERC4626 vault implementations
├── irm/                # Interest rate models
├── views/              # Read-only view contracts
├── Comptroller.sol     # Core market controller
├── MToken.sol          # Market token base
test/
├── unit/               # *.t.sol files
├── integration/        # End-to-end tests
├── fuzzing/            # Fuzz tests
├── certora/            # Formal verification
proposals/
├── mips/               # All governance proposals (mip-b##, mip-x##, mip-m##, mip-o##)
├── templates/          # MarketAdd, MarketUpdate, RewardsDistribution
├── proposalTypes/      # HybridProposal, GovernanceProposal
├── Addresses.sol       # Per-chain address registry
chains/                 # Chain config JSONs keyed by chain ID (1, 8453, 10, 1284)
script/                 # Deployment & utility scripts (~53)
```

## Common Commands

- `forge build` — compile contracts
- `forge test` — run all tests
- `make test-unit` — unit tests only
- `make coverage` — coverage report
- `make slither` — static analysis
- `npm run lint` — solhint
- `npm run prettier` — format code
- `make base` / `make moonbeam-node` — local chain forks

## Proposal System

Proposals follow a lifecycle: `deploy()` → `afterDeploy()` → `build()` →
`simulate()` → `validate()`

**Naming convention:**

- `mip-b##` — Base chain
- `mip-x##` — Ethereum/cross-chain
- `mip-m##` — Moonbeam
- `mip-o##` — Optimism

**Creating a new proposal:**

1. Set `id: 0` in `proposals/mips/mips.json` for new entries
2. Create folder in `proposals/mips/mip-{chain}{number}/`
3. Add `.sh` (env vars: JSON_PATH, DESCRIPTION_PATH, PRIMARY_FORK_ID), `.json`,
   `.md`
4. Use existing templates from `proposals/templates/` when applicable

**Templates available:** MarketAdd (v1/v2/v3), MarketUpdate,
RewardsDistribution, ProtocolDeployment

## Key Conventions

- Addresses managed centrally in `proposals/Addresses.sol` + `chains/*.json`
- Tests use `*.t.sol` suffix, inherit from `Test` or `PostProposalCheck`
- RPC endpoints configured in `foundry.toml` for all supported chains
- EVM target is Cancun
- Optimizer runs: 1

## Guardrails

- Always set `id: 0` in mips.json when creating new proposals
- Scan ALL related contracts before concluding something is unused — cross-chain
  dependencies are easy to miss
- Check chain-specific configs in `chains/` when working with deployments
- Run `forge test` before committing contract changes

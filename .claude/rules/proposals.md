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

# Cross-Chain Rules

- Chain configs live in `chains/` keyed by chain ID: 1 (Ethereum), 8453 (Base),
  10 (Optimism), 1284 (Moonbeam)
- Governance hub is MultichainGovernor on Moonbeam — proposals execute
  cross-chain via Wormhole
- xWELL token bridges via Axelar
- When modifying cross-chain logic: test on ALL affected chains, not just one
- Always verify Wormhole message encoding matches the receiving
  TemporalGovernor's expectations
- Check `envpath` vs `envPath` inconsistency in mips.json — both exist
  historically

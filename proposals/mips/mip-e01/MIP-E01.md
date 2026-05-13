# MIP-E01: First Ethereum Proposal — Complete Cross-Chain Ownership Transfers

## Summary

The first proposal submitted to the new `MultichainGovernorV2` on Ethereum.
Completes the ownership/admin transfers that MIP-X56 and MIP-E00 leave in a
half-transferred state.

## Why this is needed

MIP-X56 and MIP-E00 either set `pendingOwner`/`pendingAdmin` on contracts they
couldn't immediately accept on, or relied on follow-up proposal execution from
the new governor. Specifically:

- **Ethereum xWELL** — `PostDeployEthereumXWell.s.sol` sets
  `pendingOwner = MultichainGovernorV2`. No proposal accepts.
- **Ethereum VotingPowerAggregator** — MIP-X56 `afterDeploy` sets
  `pendingOwner = MultichainGovernorV2`. No proposal accepts.
- **Moonbeam mTokens + Unitroller** — MIP-X56's proposal calls
  `_setPendingAdmin(TemporalGovernor)` on every Moonbeam mToken whose admin was
  the old `MultichainGovernor`, plus the Unitroller. The `_acceptAdmin()` calls
  require `msg.sender == pendingAdmin` (TemporalGovernor), which can only happen
  via a cross-chain message from the new Ethereum governor → Moonbeam TG →
  executeProposal.

## Proposal Actions

### Ethereum (executed directly by MultichainGovernorV2)

1. `xWELL.acceptOwnership()` — completes the Ownable2Step transfer started by
   PostDeployEthereumXWell.
2. `VotingPowerAggregator.acceptOwnership()` — completes the Ownable2Step
   transfer started by MIP-X56 `afterDeploy`.

### Moonbeam (executed by TemporalGovernor via Wormhole)

3. `Unitroller._acceptAdmin()` — completes the admin transfer started by
   MIP-X56.
4. For every Moonbeam mToken with `pendingAdmin == TemporalGovernor`:
   `mToken._acceptAdmin()` — completes the admin transfer.

## What this proposal does NOT cover

- **xWELL bridging activation** (`addTrustedSenders` on the four
  `WormholeBridgeAdapter` contracts to enable Ethereum ↔ satellite bridging).
  That's handled by a separate in-flight Moonbeam-governor proposal so users can
  bridge xWELL to Ethereum **before** the new governor goes live, ensuring
  voting power exists on Eth at MIP-X56 execution time.

## Post-execution validation

- `xWELL.owner() == MultichainGovernorV2`
- `VotingPowerAggregator.owner() == MultichainGovernorV2` (on Ethereum)
- `Unitroller.admin() == TemporalGovernor` (on Moonbeam)
- Every Moonbeam mToken: `admin() == TemporalGovernor`

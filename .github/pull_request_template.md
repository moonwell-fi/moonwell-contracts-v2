## Summary

<!-- One or two sentences: what does this PR do and why. -->

## Simulation output

<!-- For MIPs: paste the proposal description, actions, and calldata from
`forge script ... --sig "printProposalActionSteps()"` or the default run.
Delete this section if the PR does not touch `proposals/`. -->

## Notes

<!-- Forum links, context, follow-ups, anything reviewers should know. -->

---

## Checklist

**General**

- [ ] `forge build` clean (no new warnings)
- [ ] `forge test` passing locally for new/modified tests
- [ ] `npm run lint` and `npm run prettier` clean
- [ ] `make slither` reviewed (no new findings, or findings justified in PR)
- [ ] Ran `@security-auditor` agent against new/modified contracts
- [ ] All CI checks green

**If this PR adds a new MIP**

- [ ] `id: 0` set in `proposals/mips/mips.json`
- [ ] Folder `proposals/mips/mip-{chain}{number}/` contains the three required files: `.sh`, `.json`, `.md`
- [ ] `.sh` sets `JSON_PATH`, `DESCRIPTION_PATH`, `PRIMARY_FORK_ID`
- [ ] New addresses live in `proposals/Addresses.sol` or `chains/*.json` — nothing hardcoded
- [ ] Forum discussion linked in the PR body (required for risk-parameter changes and market adds)
- [ ] For cross-chain proposals: simulated on every affected `PRIMARY_FORK_ID`
- [ ] Wormhole message encoding matches the receiving `TemporalGovernor` expectations

**If this PR modifies existing protocol state** (oracle swaps, proxy upgrades, IRM changes, comptroller config)

- [ ] `beforeSimulationHook()` captures downstream outputs (prices, rates, balances)
- [ ] `validate()` asserts those outputs are preserved (see MIP-B57 pattern)

**Proposal summary bot**

- [ ] Reviewed the `<!-- proposal-summary -->` comment from the `Proposal Summary` workflow
- [ ] Addressed any flagged gaps or mismatches
- [ ] Deleted the stale comment before pushing changes (forces the workflow to regenerate)

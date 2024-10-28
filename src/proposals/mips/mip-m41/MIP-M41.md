# MIP-M41: Reduce Safety Module Cooldown Period to 7 Days on Moonbeam

## Summary:

This proposal seeks to reduce the cooldown period for the Safety Module on
Moonbeam from 10 days to 7 days, aligning it with the cooldown period
adjustments
[recently implemented on Base and Optimism](https://moonwell.fi/governance/proposal/moonbeam?id=140).
Unlike on Base and Optimism, the Safety Module on Moonbeam required a contract
upgrade to implement this change. This upgrade has been rigorously audited by
Halborn Security, with a clean report and no issues identified, ensuring a
secure and seamless transition.

## Technical Implementation:

Upon successful execution, the following actions will be taken:

- Call `setCoolDownSeconds` on the stkWELL contract (Moonbeam).
  - New value: 604800 seconds (equivalent to 7 days).
- Upgrade the Moonbeam Safety Module implementation via the proxy admin.

## Frequently Asked Questions:

1. **What does this proposal do?** This change completes the transition
   initiated in MIP-X05, ensuring that the Safety Module across all networks
   functions consistently with a 7-day cooldown period, providing WELL stakers
   with feature parity regardless of the network they stake on.

2. **How does this impact unstaking?** Once this proposal is executed, WELL
   stakers on Moonbeam will experience the same 7-day cooldown period for
   unstaking WELL that is already in place on Base and Optimism.

3. **Has this change been audited?** Yes, the stkWELL contract on Moonbeam has
   undergone a security audit by Halborn Security with no issues identified.

## Timeline:

- **Voting Period:** 3 days
- **Implementation:** Immediate upon successful execution.

## Voting Options:

- For (Aye): Vote in favor of implementing the reduced cooldown period on the
  Moonbeam Safety Module.
- Against (Nay): Vote against implementing these changes, maintaining current
  cooldown period on Moonbeam.
- Abstain: Participate in voting while remaining neutral on the proposal

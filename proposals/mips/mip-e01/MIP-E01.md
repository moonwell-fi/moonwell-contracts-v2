# MIP-E01: Moonwell WETH Market Improvement

## Summary

This MIP enhances the user experience of the WETH market on Moonwell's Ethereum
deployment. Today, users who redeem their mWETH or borrow from the WETH market
receive Wrapped ETH (WETH) rather than native ETH, forcing them to manually
unwrap before using their funds elsewhere in the Ethereum ecosystem. This
proposal points the WETH market's logic contract at an `MWethDelegate`
implementation so that redemptions and borrows pay out raw ETH directly, as part
of the same transaction.

## Motivation

This proposal brings the Ethereum WETH market in line with the existing Base
deployment (MIP-B02) and delivers two user-facing improvements:

1. **Redemptions and borrows in native ETH:** Users redeeming mWETH and
   borrowers drawing from the WETH market will receive raw ETH directly,
   eliminating the manual unwrap step.
2. **Integrated WETH unwrapping:** A dedicated `WethUnwrapper` contract converts
   WETH to ETH transparently and forwards it to the end user as part of the
   protocol's existing transfer-out flow.

## Implementation Details

Two contracts are deployed as part of this proposal, and one governance action
is executed:

1. **WethUnwrapper Contract:** A minimal, immutable contract that receives WETH
   from the WETH market, calls `withdraw` to convert it to raw ETH, and forwards
   the ETH to the recipient. It only accepts ETH from the WETH contract.
2. **MWethDelegate Contract:** A new logic contract for the WETH market that
   overrides `doTransferOut` to route the underlying WETH through the
   `WethUnwrapper` before it reaches the user.

The `MWethDelegate` and `WethUnwrapper` contracts are the same designs already
audited and deployed on Base as part of MIP-B02. Moonwell's audit reports are
available [here](https://docs.moonwell.fi/moonwell/protocol-information/audits).

## Voting Options

- **Yes:** Support enabling native ETH redemptions and borrows on the Ethereum
  WETH market.
- **No:** Keep the status quo (redemptions and borrows paid out in WETH).
- **Abstain:** Remain neutral.

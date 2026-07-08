# # MIP-M45: Moonbeam Sunset

## Summary

This proposal supports the Moonbeam Sunset by taking two actions on Moonwell’s
Moonbeam deployment:

1. Withdraw the safe portion of protocol reserves from selected Moonbeam
   markets.
2. Pause new supplying and borrowing across all live Moonbeam markets.

The withdrawn reserves will be transferred to the Foundation-designated wallet:

`0x9917Ea34179D87F06C8b9D4AfB8BD78248B434ef`

This proposal does not affect Moonwell markets on Base, Optimism, or Ethereum.
**Importantly, all withdraws made will go toward repaying bad debt in the GLMR
markets.**

## Background

Moonwell is in the process of sunsetting its Moonbeam deployment. As part of
this process, governance should reduce ongoing activity on Moonbeam and move
available protocol-owned reserves out of the Moonbeam markets. This helps
simplify the sunset process while preserving a margin of safety for existing
market conditions.

This proposal only withdraws reserves that are considered safe to withdraw from
each market. It also pauses new minting and borrowing so that additional market
activity does not continue growing on the Moonbeam deployment.

## Proposal

This proposal does two things:

### 1. Withdraw Available Protocol Reserves

Moonwell will withdraw available reserves from five Moonbeam markets and
transfer those assets to the Foundation-designated wallet.

The proposed reserve withdrawals are:

| Market  | Amount to Withdraw |
| ------- | -----------------: |
| xcUSDT  |          22,227.75 |
| xcUSDC  |          15,795.89 |
| USDC.wh |          54,800.43 |
| ETH.wh  |               8.58 |
| BTC.wh  |               0.37 |

The GLMR market is not included in the reserve withdrawal because its
outstanding borrows are greater than its reserves. GLMR will only be paused.

The xcDOT and FRAX markets are also not included. Both carry bad debt, and their
reported protocol reserves are not backed by tokens that can be transferred out
— in xcDOT's case, users exiting the market have already withdrawn nearly all of
the xcDOT it physically held. xcDOT and FRAX will only be paused.

### 2. Pause New Supplying and Borrowing

This proposal also pauses new supplying and borrowing on all live Moonbeam
markets:

- GLMR
- xcDOT
- xcUSDT
- xcUSDC
- USDC.wh
- FRAX
- ETH.wh
- BTC.wh

This means users will no longer be able to open new supply or borrow positions
on Moonbeam after the proposal is executed.

## Rationale

Pausing new supplying and borrowing helps prevent additional market activity
from building up on a deployment that is being sunset.

Withdrawing available protocol reserves allows Moonwell governance and the
Foundation to continue the Moonbeam Sunset process in an orderly way.

The withdrawal amounts are sized conservatively, using only the portion of
reserves that is safe to withdraw from each market.

## Voting Options

- Yes: Approve the Moonbeam Sunset reserve withdrawals and pause new supplying
  and borrowing on all live Moonbeam markets.
- No: Do not approve these reserve withdrawals or market pauses. Moonbeam
  markets would continue operating under their current settings.
- Abstain: Neutral.

## Conclusion

MIP-M45 sunsets Moonbeam. It withdraws available protocol reserves from selected
Moonbeam markets, transfers them to the Foundation-designated wallet, and pauses
new supplying and borrowing across all live Moonbeam markets.

These actions help reduce new activity on Moonbeam and support an orderly
wind-down of Moonwell’s Moonbeam deployment.

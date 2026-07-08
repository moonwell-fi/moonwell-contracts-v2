# MIP-M45: Moonbeam Sunset — Withdraw Reserves and Pause Markets

## Summary

As part of the Moonbeam Sunset, this proposal:

1. Withdraws the safe portion of protocol reserves from seven Moonbeam markets
   and transfers the underlying tokens to the Foundation-designated wallet
   `0x9917Ea34179D87F06C8b9D4AfB8BD78248B434ef`.
2. Pauses minting and borrowing on every live Moonbeam market.

## Reserve Withdrawals

The amount safe to withdraw from each market is its total reserves minus its
total borrows, rounded to 2 decimal places. ETH.wh and BTC.wh are rounded down
an additional 0.01 to stay under the live on-chain margin.

| Market  | Reserves (tokens) | Total Borrows | Reserves − Borrows |  Withdraw |
| ------- | ----------------: | ------------: | -----------------: | --------: |
| xcUSDT  |         32,038.89 |      9,811.14 |          22,227.75 | 22,227.75 |
| xcUSDC  |         18,458.19 |      2,662.30 |          15,795.89 | 15,795.89 |
| xcDOT   |         46,897.09 |      3,302.77 |          43,594.32 | 30,000.00 |
| USDC.wh |         60,701.98 |      5,901.55 |          54,800.43 | 54,800.43 |
| FRAX    |            536.74 |         63.33 |             473.41 |    473.41 |
| ETH.wh  |              9.42 |          0.83 |               8.59 |      8.58 |
| BTC.wh  |              0.40 |          0.02 |               0.38 |      0.37 |

The GLMR market has negative reserves-minus-borrows (5,338,499 GLMR reserves
against 14,529,316 GLMR borrows) and is excluded from the withdrawal; it is only
paused.

The xcDOT withdrawal is capped below reserves-minus-borrows: the market's
`getCash()` reports ~550,562 DOT, but ~513,407 of that is `badDebt()` tracked by
the bad-debt fixer delegate — the market physically holds only ~35,942 xcDOT,
and that balance is trending down as suppliers exit the sunsetting market. The
withdrawal is sized to 30,000 xcDOT (~1.2x cash buffer at sizing time) so the
proposal cannot revert if market activity moves cash before execution. The
physical balance will be re-verified immediately before the proposal is
submitted on-chain.

Each withdrawal is executed as `_reduceReserves(amount)` on the market — which
sends the underlying to the market admin (the Moonbeam Temporal Governor) —
followed by an ERC20 `transfer(recipient, amount)` to the Foundation-designated
wallet.

## Pause Mint and Borrow

Minting and borrowing are paused via the Comptroller (`_setMintPaused` /
`_setBorrowPaused`) on all eight live markets:

GLMR, xcDOT, xcUSDT, xcUSDC, USDC.wh, FRAX, ETH.wh, and BTC.wh.

Borrowing on FRAX is already paused; the action is included for uniformity and
is a no-op.

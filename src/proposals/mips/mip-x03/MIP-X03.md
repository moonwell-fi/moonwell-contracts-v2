# MIP-X03: Add Wrapped rsETH (wrsETH) Market to Moonwell on Base and Optimism

## Summary

This multi-network proposal seeks to onboard
[Wrapped rsETH (wrsETH)](https://kelp.gitbook.io/kelp), a liquid restaking token
from [KelpDAO](https://kelpdao.xyz), as a new collateral asset on Moonwell's
deployments on Base and Optimism.

wrsETH is a wrapped version of KelpDAO's restaked ETH (rsETH), designed to offer
liquidity and DeFi utility for restaked ETH within KelpDAO's platform. Restakers
mint rsETH by staking their liquid staking tokens (LSTs), and wrsETH enables
those tokens to be used in other DeFi apps while still earning restaking
rewards. The integration of wrsETH into Moonwell's ecosystem will create new
opportunities for users to earn Kelp Miles and EigenLayer points while supplying
or borrowing against wrsETH.

For additional details on wrsETH and Gauntlet's full risk analysis, please refer
to the forum post
[here](https://forum.moonwell.fi/t/add-wrseth-market-to-moonwell-on-base-optimism/1144).

## Gauntlet's Initial Risk Parameters

| **Parameter**            | **Base**    | **Optimism** |
| ------------------------ | ----------- | ------------ |
| **Collateral Factor**    | 74%         | 74%          |
| **Supply Cap**           | 1075 wrsETH | 400 wrsETH   |
| **Borrow Cap**           | 430 wrsETH  | 160 wrsETH   |
| **Protocol Seize Share** | 3%          | 3%           |
| **Reserve Factor**       | 0.15        | 0.15         |
| **Interest Rate Model**  |             |              |
| **Base Rate**            | 0%          | 0%           |
| **Kink**                 | 35%         | 35%          |
| **Multiplier**           | 15%         | 15%          |
| **Jump Multiplier**      | 450%        | 450%         |

### Token Addresses

- **Base**:
  [0xEDfa23602D0EC14714057867A78d01e94176BEA0](https://basescan.org/token/0xEDfa23602D0EC14714057867A78d01e94176BEA0)
- **Optimism**:
  [0x87eEE96D50Fb761AD85B1c982d28A042169d61b1](https://optimistic.etherscan.io/token/0x87eEE96D50Fb761AD85B1c982d28A042169d61b1)

### Oracle Addresses

- **Base**:
  - [RSETH/ETH](https://basescan.org/address/0xd7221b10FBBC1e1ba95Fd0B4D031C15f7F365296)
- **Optimism**:
  - [RSETH/ETH](https://optimistic.etherscan.io/address/0x03fe94a215E3842deD931769F913d93FF33d0051)

## Voting Options

- **Aye**: Approve the proposal to onboard Wrapped rsETH on both Base and
  Optimism with Gauntlet's specified initial risk parameters.
- **Nay**: Reject the proposal.
- **Abstain**: Abstain from voting on this proposal.

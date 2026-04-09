# MIP-B59: Add VVV Market to Moonwell on Base

## Summary

This proposal seeks to onboard $VVV, the native utility token of
[Venice](https://venice.ai/), as a new collateral asset on Moonwell's Base
deployment. Venice is a privacy-first AI platform providing private, uncensored
access to 100+ AI models across text, image, code, video, audio, music, and
speech. Unlike mainstream AI platforms that collect, monitor, and monetize user
data, Venice processes all requests with zero data retention. The platform
serves over 2 million users across web, mobile, and API.

VVV holders stake for yield and lock their tokens to mint DIEM — Venice's API
credit token where 1 DIEM = $1 USD in inference credits, refreshing daily when
staked. This creates a sustainable model where token holders receive ongoing,
zero-marginal-cost access to Venice's inference capacity proportional to their
stake.

## Token Information

- **Name:** Venice Token (VVV)
- **Token Standard:** ERC-20 on Base
- **Max Total Supply:** 112,568,842 VVV
- **Circulating Supply:** 44,498,220 VVV
- **Token Contract:**
  [0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf](https://basescan.org/token/0xacfE6019Ed1A7Dc6f7B508C02d1b04ec88cC21bf)
- **Price Feed:**
  [Chainlink VVV/USD](https://basescan.org/address/0xaABc55Ca55D70B034e4daA2551A224239890282F)

## Anthias' Risk Analysis and Recommendations

### Initial Risk Parameters

| **Parameter**          | **Value**   |
| ---------------------- | ----------- |
| Collateral Factor (CF) | 50%         |
| Reserve Factor         | 35%         |
| Seize Share            | 3%          |
| Supply Cap             | 170,000 VVV |
| Borrow Cap             | 0.1 VVV     |
| Base Rate              | 0%          |
| Multiplier             | 0.16        |
| Jump Multiplier        | 3.5         |
| Kink                   | 35%         |

### Projected APYs

With a reserve factor of 35%

| Utilization | Borrow APY | Supply APY |
| ----------- | ---------- | ---------- |
| 0%          | 0%         | 0%         |
| 35% (kink)  | 5.60%      | 1.27%      |
| 100%        | 200.60%    | 130.39%    |

### Oracle Configuration

Chainlink VVV/USD market price oracle.

Address:
[0xaABc55Ca55D70B034e4daA2551A224239890282F](https://basescan.org/address/0xaABc55Ca55D70B034e4daA2551A224239890282F)

## Voting Options

- **Aye:** Approve the proposal to activate a core lending market for $VVV on
  Base with Anthias' specified initial risk parameters.
- **Nay:** Reject the proposal.
- **Abstain:** Abstain from voting on this proposal.

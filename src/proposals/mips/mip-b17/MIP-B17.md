# MIP-B17 - Onboard rETH as collateral on Base deployment

## Summary

Gauntlet proposes onboarding AERO as collateral on Moonwell Base deployment. Due
to the market demand and growth of AERO liquidity on Base we think it is
appropriate to list the asset.

This proposal has been meticulously developed in accordance with our Moonwell
Asset Listing Framework v2 4, ensuring all critical details necessary for
introducing a new asset are thoroughly addressed. Given that AERO is an
established asset on Base with robust on-chain liquidity and DEX support, most
required data points are readily available and included in this document.

In line with the procedures established by the Moonwell Asset Listing Framework
v2, Gauntlet plans to submit this proposal for a Snapshot signal vote shortly.
Should this vote pass, and following the implementation of our initial risk
parameter recommendations, Gauntlet will work with other Moonwell contributors
to help initiate the AERO market smart contract prior to the on-chain activation
vote.

## General Information

Asset Name: AERO Address: 0x940181a94A35A4569E4529A3CDfB74e38FD98631 Project
Description: Aerodrome Finance is a next-generation AMM designed to serve as
Base’s central liquidity hub, combining a powerful liquidity incentive engine,
vote-lock governance model, and friendly user experience. Aerodrome inherits the
latest features from its sister protocol Velodrome V2Maybe a second bullet
underneath that briefly describes AERO. Token Description: AERO is the native
utility token of Aerodrome Finance. Aero holders can vote-escrow their tokens
(converting them to veAERO) for up to 4 years to participate in governance and
earn protocol fees. Benefits to Moonwell Community: Expands Moonwell’s stable of
supported assets. Bolsters the synergy between Moonwell and Aerodrome, the top
two DeFi projects in the Base ecosystem. This continued collaboration can lead
to increased adoption through cross-pollination of user bases. Allows WELL
tokenholders providing liquidity on Aerodrome to utilize their earned AERO
directly on Moonwell.

### Resources:

Website 3 Twitter Medium Documentation Market Risk Assessment Gauntlet has
developed custom risk parameters for the AERO token launch, based on our models
and best practices.

Parameters Values CF 0% (Expected 70%) Supply Cap 6,000,000 ($10,000,000) Borrow
Cap 3,000,000 ($5,000,000) Protocol Seize Share 3% IR Recommendations IR
Parameters Recommended Base 0 Kink 0.45 Multiplier 0.07 Jump Multiplier 3.15
Reserve Factor 0.25 Supporting Data Market Overview

Screenshot 2024-04-16 at 4.01.39 PM Screenshot 2024-04-16 at 4.01.39 PM 833×522
29.5 KB Metric Value Market Cap $675,508,415 30D AVG Volume (CEX+DEX)
$44,710,212 Circulating Supply 402,444,318 Herfindahl Index 0.0284 Volatility &
Max DD

Screenshot 2024-04-17 at 11.02.17 AM Screenshot 2024-04-17 at 11.02.17 AM
805×566 18.3 KB The maximum and minimum daily log returns for AERO are 65.5% and
-26.6% respectively over the past 60 days. We consider the minimum daily log
returns as a suitable benchmark for setting Collateral Factor, giving the max CF
at ~74% however, to be more conservative we recommend a starting CF of 0% to
test the market and expect to reach an ideal state with CF of 70%.

## TVL

Screenshot 2024-04-16 at 4.30.57 PM Screenshot 2024-04-16 at 4.30.57 PM 800×315
19.2 KB The TVL of the protocol has grown exponentially to a total of $1.43bn,
Aerodrome is the largest DEX on Base. Gauntlet deems this TVL adequate to
classify AERO as an asset that has inherent value/use cases and to be a listable
asset on Moonwell Base market.

## Supply and Borrow Caps

Screenshot 2024-04Fila-16 at 10.20.21 AM

Borrow and supply caps are the primary parameter recommendations we can make to
mitigate protocol risk when listing new assets. Gauntlet recommends setting the
borrow and supply caps strategically with available liquidity on-chain. There is
sufficient liquidity to trade upto $20M worth of AERO tokens with a slippage of
25% signalling a maximum cap setting of 12M AERO tokens. However, we recommend a
more conservative supply cap of 6M AERO tokens and 3M AERO tokens for borrow cap
to bootstrap the market. Gauntlet will continue to monitor these caps and
increase them with respect to market demand and liquidity.

## Token Concentration Risks

As with governance tokens, there have been incidents (Curve) where large sums of
tokens were used as collateral to borrow on lending protocols. Gauntlet suggests
that such risks can be averted by applying conservative Caps along with using
the Herfindahl Index to gauge token concentration across wallets.

The Herfindahl Index serves as a measure of fund concentration within addresses
on the network, offering insight into the distribution of funds among
participants. In our context, the “market” encompasses the total supply held in
externally owned accounts (EOAs), while the “market share” denotes the relative
balance of each address compared to this total supply. Consequently, the
Herfindahl Index condenses this information into a single value, reflecting the
extent of token concentration across network addresses.

Scoring between 0 and 1, the Herfindahl Index provides a clear indication of
supply concentration: higher scores signify significant concentration, whereas
lower scores suggest a more balanced distribution of funds among addresses.
Specifically, it aids in pinpointing tokens where a single entity holds a
substantial portion of the token supply.

Our findings show that excluding major smart-contracts that are of either AMM or
staking pools, the HI of AERO is 0.0284 suggesting a more evenly distributed
ownership across the network.

## IR Parameter Specifications

### AERO IR Curves

Screenshot 2024-04-17 at 10.52.22 AM Screenshot 2024-04-17 at 10.52.22 AM
800×577 32.2 KB Utilization Borrow APR Supply APR 0% 0 0 45% 3.15% 1.06% 100%
176.4% 132.3% We recommend an IR curve similar to other assets on the protocols,
with a kink at 45% and borrow APR of 3.15% at kink.

Smart Contract Risk Github Repo Contracts 1 Age of Token: 234 Days Number of
token contract transactions: 5,786,593 Is it upgradeable? No, the token contract
is not upgradeable. It does not use any proxy or upgradeability patterns.
Decentralization Top 10 Holders Privileged Roles: ”minter” - The address that
has the right to mint new tokens. Initially set to the contract deployer, and
can be changed by the current minter using the setMinter function. ”owner” - Set
to the contract deployer. However, the owner variable is private and not used in
any function, so it doesn’t have any special privileges in the current code. Is
the token pausable?\* No, the token is not pausable. Does the token have a
blacklist? No, the token does not have a blacklist functionality. Oracle
Assessment Oracle Price Feed: The official Chainlink oracle price feed address
for the $AERO token on the Base network is AERO/USD 2. On what network does the
underlying asset exist? Base Asset Nature: The $AERO token is not a synthetic,
wrapped, or staked version of any underlying asset. It operates independently on
the Base network To access more detailed information about the $AERO token’s
Chainlink oracle price feed, please visit the Chainlink price feed documentation
page here 2. Conclusion The addition of AERO to Moonwell Base presents a
strategic opportunity to enhance the diversity and robustness of protocol asset
offerings. The risk analysis by Gauntlet, alongside the strong market
performance and liquidity of AERO, supports a favorable risk profile.
Implementing this recommendation could drive further integration within the Base
ecosystem, benefiting Moonwell community and stakeholders by providing more
options for investment and collateral. We recommend proceeding with the
onboarding process, following the outlined risk parameters and monitoring the
market response closely to make any necessary adjustments in the future.

Gauntlet invites the Moonwell community to delve into this proposal, share
insights, and help shape our collective future. Your feedback is invaluable as
we weigh the benefits and considerations of activating an AERO market on
Moonwell. In the following days, Gauntlet and contributors will move forward
with an off-chain signal vote to help further gauge community sentiment.

### Disclaimer

As specified in the Asset Listing Framework v2 4, Gauntlet does not cover smart
contract risks or any technical risks. Any of the smart contract or technical
risk references or guidelines provided in this document are provided as general
best practices by either Gauntlet or the Moonwell community. We defer to
auditors with expertise in smart contract risk to provide their assessment.

Onboarding new collateral assets is inherently a risky process and contains
several strategic decisions the community has to make, with tools the community
decides to use.

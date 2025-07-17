# MIP-M44: Switching all Moonbeam Markets to using API3's Data Feeds to Maximize OEV Recapture

**Author:** Dave Connor, API3

**Related Discussions:**
https://forum.moonwell.fi/t/switching-moonwells-glmr-market-to-using-api3s-oev-enabled-data-feed-for-glmr/1530

[Moonwell Governance Call: December 2024](https://www.youtube.com/watch?time_continue=525&v=UIqNapXXrqA&embeds_referring_euri=https%3A%2F%2Fforum.moonwell.fi%2F&source_ve_path=Mjg2NjY)

**Submission Date:** 09/07/2025

**Summary**

Moonwell recently switched to using API3 to supply price data for GLMR/USD on
Moonwell's Moonbeam market. This proposal seeks to boost the yield that
Moonwell's Moonbeam deployment generates by switching to using API3’s dAPIs
(data feeds) for all markets. API3’s OEV data feeds have been used in production
without problems for months by many lending markets, including Compound V2 forks
(like Moonwell) and Compound. Switching the remaining markets on Moonwell to
using API3 would simply involve changing the addresses that the data feeds are
read from, as with the switch for GLMR/USD.

This proposal does not compete with The Solidity Labs onchain OEV solution
currently used by Moonwell on Superchain L2s, which is expected to not reliably
work on chains where MEV exists, such as Moonbeam.

Similarly, while this proposal directs the revenue from OEV to the addReserves
function of the GLMR core maket on Moonbeam, there are many alternatives that
could be explored in future proposals from the Moonwell community, such as
reducing effective liquidation penalties.

**Overview**

A more detailed description of how API3’s OEV solution works can be found in the
[previous proposal](https://forum.moonwell.fi/t/switching-moonwells-glmr-market-to-using-api3s-oev-enabled-data-feed-for-glmr/1530),
and in Api3’s [docs](https://docs.api3.org/oev-searchers/). There is also a
[video](https://www.youtube.com/watch?time_continue=525&v=UIqNapXXrqA&embeds_referring_euri=https%3A%2F%2Fforum.moonwell.fi%2F&source_ve_path=Mjg2NjY)
which looks into the differing approaches to OEV design between Solidity Labs
and API3 in more detail.

Since GLMR/USD was switched from Chainlink to API3 in late April, API3 helped
return over \$680 to Moonwell on Moonbeam, via the addReserves function on the
contract. The OEV returned to Moonwell represented approximately 87% of
potential value that could have been recaptured, which can be used as a more
reliable figure to demonstrate performance than absolute $ value, which will be
low during periods of time where market volatility is lower. A breakdown of
this, showing all liquidations, can be seen
[here](https://oev-dashboard.api3.org/#/dapps/moonwell-moonbeam?query=GLMR&from=2025-04-24&to=2025-06-04).
Note that the OEV Dashboard shows all Moonwell liquidations on Moonbeam, so
currently underreports OEV percentage. The link in the previous sentence filters
by asset, and is more accurate. Switching all feeds over to API3 will help
improve the number of liquidations that can have OEV recaptured, as well as the
value returned.

This proposal will switch all data feeds used by Moonwell on Moonbeam to API3,
which will improve the value recaptured further.

**Motivation**

The Solidity Labs onchain OEV solution currently used by Moonwell on Superchain
L2s is expected to not reliably work where MEV exists, like on Moonbeam. In
order to be able to recapture OEV, an alternative solution is needed. API3 has
proven the viability of their OEV solution on the GLMR market, and this proposal
will extend it to all markets, maximising recapture for Moonwell on Moonbeam.

This can act as a proof of concept for Moonwell, as API3 are willing to support
Moonwell's cross chain expansion plans, and API3 enable recapture on chains even
if MEV is available.

**Implementation**

API3 will ensure every feed currently used by Moonwell on Moonbeam is live and
ready to be used. Moonwell will switch from reading prices from Chainlink's data
feeds to equivalent pairs API3’s dAPIs.

The GLMR market has already been switched to using API3. Should this proposal
pass, the other markets on Moonwell's Moonbeam deployment will utilise the
following feeds from API3:

xcDOT - DOT/USD

FRAX - FRAX/USD

xcUSDT - USDT/USD

xcUSDC - USDC/USD

ETH.wh - ETH/USD

BTC.wh - BTC/USD

USDC.wh - USDC/USD

These feeds are already live and available at the time of this proposal, and can
be viewed, and first party sources verified, on market.api3.org

OEV accrued will be distributed to the GLMR core market on Moonbeam's reserves
using the addReserve function. This process will be visible onchain and
verifiable by Moonwell community members. API3 maintains a dashboard showing
these metrics as well, available at https://oev-dashboard.api3.org/. For viewing
current OEV statistics, note that filtering by asset is necessary, as it
currently shows all liquidations on Moonbeam. This link shows the GLMR
liquidations only to better check OEV performance -
https://oev-dashboard.api3.org/#/dapps/moonwell-moonbeam?query=GLMR&from=2025-04-24&to=2025-06-04

**Voting**

**Yay** - Moonwell will switch all current markets from using Chainlink to API3
on Moonbeam. API3 will continue distributing 80% of the OEV proceeds to
Moonwell, via the addReserves function on the GLMR core market on Moonbeam.

**Nay** - No changes will be made

**Abstain** - Abstain

Authors: Elliot, Ana

**Summary**: Activate reward emissions for WELL on Base

**Overview**

The community has recently voted to implement the new Multichain Governor
contract to govern the Moonwell Protocol. Additionally, a new multichain WELL
token utilizing the xERC20 token standard has been ratified for usage on Base,
which is a significant milestone for the community. By adopting this new Base
native WELL token, tokenholders can now stake their tokens directly on Base and
participate in onchain governance voting. The Safety Module was deployed on Base
and is registered in the Multichain Vote Collection contract as a source of
voting power, allowing users securing the protocol to participate in governance.

Initially, rewards were set to 0 on the new Safety Module on Base. This proposal
aims to enable rewards for users in the Safety Module with the new Base native
WELL token.

Before this configuration is able to occur, ample time should be given to the
community to bridge their Wormhole wrapped WELL from Base, to Moonbeam and back
in the Base native form. Initial estimates of this migration time are at minimum
6 days if all Wormhole Wrapped WELL was constantly bridged from Base back to
Moonbeam and Wormhole did not delay transfers.

Implementation: A proposal will be created by Solidity Labs that sets and funds
rewards that will be given to all Safety Module Stakers. Warden Finance will
provide recommendations on initial reward speeds.

Conclusion: Adding rewards to the Safety Module on Base creates incentives for
users to backstop the protocol with the new Base native WELL token. Staking WELL
in the Safety Module not only gives community members the ability to earn native
yield on their holdings, but also presents an easy way to get involved in
governance as WELL is automatically self delegated.

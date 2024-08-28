# MIP-O01: Optimism Activation - Part 2

I propose that the Moonwell DAO votes to authorize the activation of the
Moonwell Protocol on [Optimism](https://www.optimism.io/). By leveraging
Optimism's advanced scaling solutions, shared values, and robust funding
opportunities, we'll be able to significantly expand Moonwell's reach and
impact.

Activating Moonwell on OP Mainnet will allow Moonwell opportunities to:

1. Become the leading lending protocol on Optimism
2. Align with shared values and ecosystem goals
3. Access the Optimism Foundation's generous funding and incentives programs

## About Optimism

Optimism is an Ethereum Layer 2 (L2) blockchain network developed by OP Labs and
deployed in 2021. Utilizing
[Optimistic Rollups](https://docs.optimism.io/stack/protocol/rollup/overview),
Optimism bundles transactions off-chain and posts transaction data (blobs) to
Ethereum mainnet. It is designed to enhance scalability and reduce transaction
costs while maintaining the security that Ethereum mainnet provides. The recent
implementation of [EIP-4844](https://www.eip4844.com/) and "blobspace" has
further reduced transaction fees on both Base and Optimism, aligning with the
Moonwell community's mission of making onchain finance accessible to everyone.

Optimism shares foundational technological and philosophical principles with
Base, which
[Moonwell was activated](https://forum.moonwell.fi/t/mip-39-activate-moonwell-on-base-mainnet/414)
on in March 2023. Optimism and Base are both built on the
[OP Stack](https://docs.optimism.io/), a set of MIT-licensed open-source
software designed to enhance Ethereum's scalability and modularity. The OP Stack
facilitates the creation of interoperable Layer 2 solutions, contributing to a
larger "Superchain" vision where multiple Layer 2 networks can operate
cohesively. Optimism and Base are both committed to the Retroactive Public Goods
Funding (RetroPGF) model, which incentivizes the development of open-source
projects that benefit the entire Superchain ecosystem.

Since its inception in 2021, Optimism has supported around 370 dApps and has a
Total Value Locked (TVL) of approximately $884.81 million. The network has saved
users over $1 billion in gas fees. Statistics on lending protocols on Optimism
can be found [here](https://defillama.com/chain/Optimism); as of June 16, 2024,
the lending protocols on Optimism with the highest TVL are Aave v3 ($160.5m),
Exactly ($10.08m), and Compound v3 ($6.32m). The recent exploit of the lending
protocol Sonne Finance has created a significant gap in the Optimism lending
ecosystem. This presents an ideal opportunity for Moonwell to step in and
establish itself as the go-to lending solution on the network.

Optimism's roadmap focuses on enhancing scalability and decentralization. A
significant milestone was recently achieved with the launch of
[permissionless fault proofs](https://optimism.mirror.xyz/izdAoJ8ooyhDfwFLFoCcUfB1icPLFn8AImBws4oaqw8)
on OP Mainnet, marking Optimism's arrival at Stage 1 decentralization. This
enables withdrawals without trusted third parties and allows users to challenge
invalid withdrawals. Optimism is now working towards
[Stage 2 decentralization](https://blog.oplabs.co/endgame-is-stage-2/) by
implementing multiple proof systems, including zero-knowledge proofs. The fault
proof proposal was approved by Optimism's governance process, and additional
proof systems will be rolled out on testnet to ensure reliability and
robustness.

Activating Moonwell on Optimism aligns the protocol with a network dedicated to
efficiency, accessibility, decentralization, and community-driven development,
positioning Moonwell at the forefront of the rapidly evolving Superchain
ecosystem.

## Motivation

Activating Moonwell on Optimism offers a number of benefits to the Moonwell
community, including opportunities to:

1. Become the Leading Lending Protocol on Optimism
2. Align with Shared Values and Ecosystem Goals
3. Access Optimism's Substantial Funding and Incentive Programs

### Become the Leading Lending Protocol on Optimism

There is a massive opportunity for Moonwell to capture a large portion of
lending TVL on Optimism, especially in light of the recent Sonne Finance
exploit. Aave, the current TVL leader, is a low-effort deployment lacking a
Safety Module and additional market incentives. The current state of lending on
Optimism is available [here](https://defillama.com/protocols/Lending/Optimism)
on DeFi Llama. By deploying Moonwell on Optimism, we can tap into this
established DeFi landscape, attracting a broader user base seeking efficient and
cost-effective financial services.

### Align with Shared Values and Ecosystem Goals

Moonwell and Optimism share a common vision centered on decentralization,
security, and community governance. Optimism's governance model, which includes
the [Retroactive Public Goods Funding](https://retropgfhub.com/) (RetroPGF)
initiative, aligns with Moonwell's commitment to fostering an open,
community-driven ecosystem​. See the Optimism Collective Constitution
[here](https://gov.optimism.io/t/working-constitution-of-the-optimism-collective/55).

The governance of the Moonwell Protocol on Optimism will be managed by WELL
token holders, though note that
[xWELL](https://forum.moonwell.fi/t/mip-m23-and-mip-m24-multichain-governor-and-well-migration/820#mutichain-well-xwell-9)
(multichain native, xERC-20 WELL), the multichain vote collector contract, and
the Safety Module will be activated in a later proposal following initial
activation. Halborn Security is anticipated to conduct code reviews to verify
all the deployment parameters. Moreover, Moonwell markets on Optimism will be
safeguarded against price manipulation through the use of
[Chainlink oracle price feeds](https://blog.chain.link/levels-of-data-aggregation-in-chainlink-price-feeds/).
Moonwell contributor and lead risk manager Gauntlet will conduct regular
economic simulations to confirm that asset risk parameters are maintained at
safe levels.

### Access Optimism's Funding and Incentive Programs

Optimism has well-known and extremely generous funding and incentive programs we
can leverage to bolster liquidity in our markets and drive user adoption. In
2023, the Moonwell community successfully secured a
[Retro PGF3 grant](https://optimism-agora-prod.agora-prod.workers.dev/retropgf/3/application/0xeff464a4d1163c24dea3777598667b31c6b68cea03649e0e8dbaa80fad82fc5f)
of 54,658 OP tokens and 80,156 OP for
[Retro PGF4](https://x.com/MoonwellDeFi/status/1813983656308080718). All granted
OP tokens will be used as liquidity incentives, bootstrapping markets and
further boosting the growth and adoption of Moonwell on the Optimism network.

## Proposed Markets

I propose activating the Moonwell Protocol on Optimism with the following
initial lending markets:

- WETH:
  [0x4200000000000000000000000000000000000006](https://optimistic.etherscan.io/token/0x4200000000000000000000000000000000000006)
- USDC:
  [0x0b2c639c533813f4aa9d7837caf62653d097ff85](https://optimistic.etherscan.io/token/0x0b2c639c533813f4aa9d7837caf62653d097ff85)
- USDT:
  [0x94b008aa00579c1307b0ef2c499ad98a8ce58e58](https://optimistic.etherscan.io/token/0x94b008aa00579c1307b0ef2c499ad98a8ce58e58)
- DAI:
  [0xda10009cbd5d07dd0cecc66161fc93d7c9000da1](https://optimistic.etherscan.io/address/0xda10009cbd5d07dd0cecc66161fc93d7c9000da1)
- WBTC:
  [0x68f180fcce6836688e9084f035309e29bf0a2095](https://optimistic.etherscan.io/token/0x68f180fcce6836688e9084f035309e29bf0a2095)
- wstETH:
  [0x1f32b1c2345538c0c6f582fcb022739c4a194ebb](https://optimistic.etherscan.io/token/0x1f32b1c2345538c0c6f582fcb022739c4a194ebb)
- cbETH:
  [0xaddb6a0412de1ba0f936dcaeb8aaa24578dcf3b2](https://optimistic.etherscan.io/address/0xaddb6a0412de1ba0f936dcaeb8aaa24578dcf3b2)
- rETH:
  [0x9bcef72be871e61ed4fbbc7630889bee758eb81d](https://optimistic.etherscan.io/address/0x9bcef72be871e61ed4fbbc763088)
- OP:
  [0x4200000000000000000000000000000000000042](https://optimistic.etherscan.io/address/0x4200000000000000000000000000000000000042)
- VELO:
  [0x3c8b650257cfb5f272f799f5e2b4e65093a11a05](https://optimistic.etherscan.io/address/0x3c8b650257cfb5f272f799f5e2b4e65093a11a05)

Please note that OP and VELO markets were inadvertently left off of the MIP-O00
proposal description, but are included in the OP Mainnet activation proposals.

All proposed assets already possess Chainlink price feeds and their markets will
be initially set to 0% CF to protect against the
[Hundred Finance](https://rekt.news/hundred-rekt2/) exploit. Gauntlet will be
able to update market risk parameters such as Collateral Factors following
initial market activation in their monthly risk parameter adjustment MIPs. As
with Moonwell's Base deployment, Gauntlet will also be able to adjust supply and
borrow caps dynamically through their Cap Guardian role.

## Implementation

This is a continuation of MIP-O00, which accepted admin as the Temporal Governor
and set the WELL emission configs. This governance proposal unpauses and mints a
small amount of each market's mToken to mitigate against the
[Hundred Finance](https://rekt.news/hundred-rekt2/) exploit.

MIP-O00 was originally going to be submitted as a single proposal. However, it
has been split into two activation proposals to work around the transaction gas
limit on Moonbeam.

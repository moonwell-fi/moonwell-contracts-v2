# MIP-M23: Multichain Governor Migration - Transfer Power to New Governor

## Overview

Moonwell currently utilizes Compound's
[GovernorAlpha](https://moonscan.io/address/0xfc4DFB17101A12C5CEc5eeDd8E92B5b16557666d#code)
smart contract, which has been widely used and trusted by many communities over
the years for protocol governance. However, its single-chain architecture has
limitations that prevent it from offering a seamless, cross-chain experience. As
things stand today, WELL tokenholders on Base cannot participate in governance
unless they bridge their tokens back to Moonbeam. Following Moonwell’s recent
expansion, there have been numerous calls from community members to solve this
UX issue and enable voting and staking directly on Base. To meet this need and
future-proof our governance architecture, my team at Solidity Labs has developed
a new multichain governor that aims to provide a more flexible and scalable
solution. This proposal, MIP-M23, is the first of two MIPs required to migrate
the protocol to the new governor system contracts. In this proposal, we will
deploy the new governor contracts onto Moonbeam mainnet and transfer governance
powers from the current governor to the new, multichain governor. Shortly
following this proposal, MIP-24 will be submitted, which will accept ownership
of the contracts and finalize the new governor’s abilities. By implementing this
new multichain governance model, we aim to provide the community with a more
accessible and intuitive way to participate in the decision-making process,
regardless of preferred network. This upgrade will not only cater to the needs
of our growing community, but also solidify Moonwell's position at the forefront
of onchain governance innovation.

## System Parameters

To ensure a smooth transition and maintain consistency with the current
governance model, the parameters for this new system are set to be as close to
the existing governor’s as possible. However, one notable exception is the
proposal creation threshold, which has been increased from 400,000 to 1,000,000
WELL. This adjustment was made to account for the increase in the circulating
supply of WELL tokens since the inception of Moonwell Governance in 2022.

### Starting System Parameters

- Quorum: 100,000,000 WELL
- Voting Period: 3 days
- Maximum Live Proposals per Address: 5
- Pause Duration: 30 days
- Proposal Threshold: 1,000,000
- Cross-Chain Vote Collection Period: 1 day

### Constant Values

- Minimum Cross-Chain Vote Collection Period: 1 hours
- Maximum Cross-Chain Vote Collection Period: 14 days
- Minimum Proposal Threshold: 400,000 WELL
- Maximum Proposal Threshold: 50,000,000 WELL
- Minimum Voting Period: 1 hours
- Maximum Voting Period: 14 days
- Maximum User Proposal Count: 20
- Maximum Quorum: 500,000,000
- Minimum Gas Limit = 400,000

Under this new multichain governance model, a proposal becomes executable after
a total of four days, with no voting delay. Once a proposal has been created,
voting can begin immediately. After the voting period concludes, the cross-chain
vote collection period begins, during which vote counts from all other networks,
including Base, are tallied. If a proposal reaches the quorum requirement and
receives more "yes" votes than "no'' votes, it becomes executable.

The constant values serve as a floor and ceiling for acceptable system
parameters, preventing the governor contract from being incorrectly
parameterized in obviously incorrect ways. System parameters can be adjusted by
the community through onchain voting, but the values must remain between these
boundaries. This safeguard ensures that the governance process remains stable,
secure, and aligned with the best interests of the Moonwell community.

## Implementation

Once the new contracts have been deployed and initialized, it is necessary to
transfer governance powers from the current governor to the new, multichain
governor. As part of this proposal, the following onchain actions will be
implemented:

- Set pending admin on all mToken contracts
- Set pending admin on the Comptroller
- Set Chainlink price oracle admin
- Set Wormhole Bridge Adapter pending owner
- Set xWELL pending owner
- Set trusted sender in Temporal Governor
- Set the Staked Well emission manager
- Set the Ecosystem Reserve Controller owner
- Set the the Proxy Admin owner

By completing these actions, the new multichain governor will assume governance
powers over the Moonwell Protocol, enabling cross-chain governance and user
participation from Base.

## Security

Multiple security measures were employed to verify the new code and achieve
internal confidence in its robustness. The following are the testing
methodologies and security measures employed:

- Static analysis with slither
- [Extensive unit testing](https://github.com/moonwell-fi/moonwell-contracts-v2/pull/101/files#diff-e25ffc63bb66f53458e2ce5679f04ed4fda78735f6e9ac96d95370f079840ae6)
- [Integration testing](https://github.com/moonwell-fi/moonwell-contracts-v2/pull/101/files#diff-e918183c66295bd33936cbfb53246b3e209849d595e31e6fb0e027ab842c6208)
  of the new governor and proposals to ensure ownership of system contracts are
  handed to the new governor
- Integration testing of the deployment script
- Mutation testing to understand the strength of the test suite
- Formal verification of key governance invariants, ensuring strict minimum and
  maximum values for parameters are always enforced
- Multiple internal code reviews
- A
  [week-long audit](https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/audits/Kauz_Cross-Chain-Governance_Audit.pdf)
  by Kauz Security Services, which found no high or medium issues
- A
  [3.5-week audit](https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/audits/Moonwell_Cross-Chain_Governance_Audit.pdf)
  by Halborn, which also found no high or medium issues

## Governance Guardians

The Governance Guardian role, previously known as the Break Glass Guardian,
serves as a crucial safeguard mechanism within the new multichain governance
model. In the event of an emergency or unforeseen circumstance, the Governance
Guardian role has the ability to "break glass” and roll back governance
ownership to a predetermined address, which will be set to the current governor
contract. It is important to note that the break glass function can only be used
once and must be restored through an onchain governance vote. The Governance
fGuardians will sit on a 3 of 4 multisig. I nominate myself to be one of the
four Governance Guardians, recognizing the importance of this responsibility and
my commitment to the long-term success and health of Moonwell. The complete list
of signers is currently being determined, with a focus on selecting individuals
and entities who have demonstrated expertise, integrity, and dedication to the
Moonwell Protocol and community. An additional signer will be added in the near
future to further increase the security of the multisig and ability to respond.

## Mutichain WELL (xWELL)

[xERC20](https://www.xerc20.com/) is a token standard that creates a natively
multichain ERC20 token. This token enshrines rate limits to bridge providers and
has the ability to change, or support multiple bridge providers at will. Through
the passage of this proposal, Moonwell will adopt this new token standard,
allowing for staking and governance participation on Base, as well as any future
network. At launch, the xERC20 version of WELL, which I will call xWELL for the
purposes of this proposal, will leverage Wormhole’s General Message Passing
(GMP) infrastructure to send information on user transfers between chains. With
the creation of xWELL, users will be able to participate in governance and stake
their tokens directly on Base, empowering them to actively contribute to the
protocol's security and decision-making process from their network of choice.

Currently, liquidity incentives on Moonwell's Base markets are paid out in the
Wormhole wrapped version of WELL. With the passing of this proposal, xWELL will
be introduced as a reward token on all Base markets. Initially, the
configurations will provide users with no xWELL rewards; however, Warden
Finance, serving as the emissions admin, will have the authority to enable xWELL
rewards after the next emission cycle concludes in April. From that point
forward, xWELL will replace the original Wormhole Wrapped variant as the primary
reward token.

## xWELL Security

Throughout the development of xWELL, a multitude of testing methodologies were
employed to foster a high level of confidence in its security prior to launch.
The following are the testing and security measures employed:

- [Unit Testing](https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/test/unit/xWELL.t.sol)
- [Integration Testing](https://github.com/moonwell-fi/moonwell-contracts-v2/tree/main/test/integration/xWELL)
- [Invariant Testing](https://github.com/moonwell-fi/moonwell-contracts-v2/tree/main/test/invariant)
- [Formal Verification](https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/certora/specs/ERC20.spec)
  of key system properties
- A multi-week long
  [Halborn Audit](https://github.com/moonwell-fi/moonwell-contracts-v2/blob/main/audits/Moonwell_Finance_XWell_Token_Rate-Limiting_Smart_Contract_Security_Assessment_Report_Halborn_Final_Update.pdf)
  which reviewed the xWELL token and the Wormhole Bridge Adapter.

## xWELL Parameters

The xWELL token will have the following parameters for the Wormhole Bridge
Adapters to limit throughput and increase security.

- Buffer Capacity: 100,000,000 xWELL on each chain.
- Buffer Replenish Rate: 1,158 xWELL per second. This rate is equivalent to
  100,000,000 xWELL per day and allows the midpoint to be reached within 12
  hours if the buffer is fully depleted or replenished.

The buffer depletes on minting, and replenishes on burning. The buffer is
designed to limit the creation of xWELL on each chain, ensuring that the rate of
minting and burning is controlled and secure. These parameters will likely be
lowered in the future once the initial token amounts have been moved across
chains.

### Conclusion

The migration to a multichain governance model marks a pivotal moment in the
evolution of Moonwell. By addressing the growing needs of our community and
enabling onchain voting from Base, we are taking a significant step towards
building a more inclusive, flexible, and future-proof governance structure.

d# ✨ So you want to run an audit

This `README.md` contains a set of checklists for our audit collaboration.

Your audit will use two repos: 
- **an _audit_ repo** (this one), which is used for scoping your audit and for providing information to wardens
- **a _findings_ repo**, where issues are submitted (shared with you after the audit) 

Ultimately, when we launch the audit, this repo will be made public and will contain the smart contracts to be reviewed and all the information needed for audit participants. The findings repo will be made public after the audit report is published and your team has mitigated the identified issues.

Some of the checklists in this doc are for **C4 (🐺)** and some of them are for **you as the audit sponsor (⭐️)**.

---

# Repo setup

## ⭐️ Sponsor: Add code to this repo

- [ ] Create a PR to this repo with the below changes:
- [ ] Provide a self-contained repository with working commands that will build (at least) all in-scope contracts, and commands that will run tests producing gas reports for the relevant contracts.
- [ ] Make sure your code is thoroughly commented using the [NatSpec format](https://docs.soliditylang.org/en/v0.5.10/natspec-format.html#natspec-format).
- [ ] Please have final versions of contracts and documentation added/updated in this repo **no less than 48 business hours prior to audit start time.**
- [ ] Be prepared for a 🚨code freeze🚨 for the duration of the audit — important because it establishes a level playing field. We want to ensure everyone's looking at the same code, no matter when they look during the audit. (Note: this includes your own repo, since a PR can leak alpha to our wardens!)


---

## ⭐️ Sponsor: Edit this README

Under "SPONSORS ADD INFO HERE" heading below, include the following:

- [ ] Modify the bottom of this `README.md` file to describe how your code is supposed to work with links to any relevent documentation and any other criteria/details that the C4 Wardens should keep in mind when reviewing. ([Here's a well-constructed example.](https://github.com/code-423n4/2022-08-foundation#readme))
  - [ ] When linking, please **provide all links as full absolute links** versus relative links
  - [ ] All information should be provided in markdown format (HTML does not render on Code4rena.com)
- [ ] Under the "Scope" heading, provide the name of each contract and:
  - [ ] source lines of code (excluding blank lines and comments) in each
  - [ ] external contracts called in each
  - [ ] libraries used in each
- [ ] Describe any novel or unique curve logic or mathematical models implemented in the contracts
- [ ] Does the token conform to the ERC-20 standard? In what specific ways does it differ?
- [ ] Describe anything else that adds any special logic that makes your approach unique
- [ ] Identify any areas of specific concern in reviewing the code
- [ ] Review the Gas award pool amount. This can be adjusted up or down, based on your preference - just flag it for Code4rena staff so we can update the pool totals across all comms channels. 
- [ ] Optional / nice to have: pre-record a high-level overview of your protocol (not just specific smart contract functions). This saves wardens a lot of time wading through documentation.
- [ ] See also: [this checklist in Notion](https://code4rena.notion.site/Key-info-for-Code4rena-sponsors-f60764c4c4574bbf8e7a6dbd72cc49b4#0cafa01e6201462e9f78677a39e09746)
- [ ] Delete this checklist and all text above the line below when you're ready.

---

# Moonwell audit details
- Total Prize Pool: $100,000 USDC 
  - HM awards: $69,712.50 USDC 
  - Analysis awards: $4,225 USDC 
  - QA awards: $2,112.50 USDC 
  - Bot Race awards: $6,337.50 USDC 
  - Gas awards: $2,112.50 USDC 
  - Judge awards: $9,000 USDC 
  - Lookout awards: $6,000 USDC 
  - Scout awards: $500 USDC 
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2023-07-moonwell/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts July 24, 2023 20:00 UTC 
- Ends July 31, 2023 20:00 UTC
  
## Automated Findings / Publicly Known Issues

Automated findings output for the audit can be found [here](add link to report) within 24 hours of audit opening.

*Note for C4 wardens: Anything included in the automated findings output is considered a publicly known issue and is ineligible for awards.*

[ ⭐️ SPONSORS ADD INFO HERE ]

# Overview

*Please provide some context about the code being audited, and identify any areas of specific concern in reviewing the code. (This is a good place to link to your docs, if you have them.)*

The Moonwell Protocol is a fork of Benqi, which is a fork of Compound v2 with features like borrow caps and multi-token emissions.

Specific areas of concern include:
* [ChainlinkCompositeOracle](src/core/Oracles/ChainlinkCompositeOracle.sol) which aggregates mulitple exchange rates together.
* [MultiRewardDistributor](src/core/MultiRewardDistributor/MultiRewardDistributor.sol) allow distributing and rewarding users with multiple tokens per MToken. Parts of this system that require special attention are what happens when hooks fail in the Comptroller. Are there states this system could be in that would allow an attacker to pull more than their pro rata share of rewards out? This contract is based on the Flywheel logic in the [Comptroller](https://github.com/compound-finance/compound-protocol/blob/master/contracts/ComptrollerG7.sol#L1102-L1187).
* [TemporalGovernor](src/core/Governance/TemporalGovernor.sol) which is the cross chain governance contract. Specific areas of concern include delays, the pause guardian, putting the contract into a state where it cannot be updated.

For more in depth review of the MToken <-> Comptroller <-> Multi Reward Distributor, see the Cross Contract Interaction [Documentation](CROSSCONTRACTINTERACTION.md).

# Scope

*List all files in scope in the table below (along with hyperlinks) -- and feel free to add notes here to emphasize areas of focus.*

*For line of code counts, we recommend using [cloc](https://github.com/AlDanial/cloc).* 

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [src/core/MultiRewardDistributor/MultiRewardDistributor.sol](src/core/MultiRewardDistributor/MultiRewardDistributor.sol) | 745 | This contract handles distribution of rewards to mToken holders.  | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [src/core/Comptroller.sol](src/core/Comptroller.sol) | 526 | This contract is the source of truth for the entire Moonwell protocol | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [src/core/Unitroller.sol](src/core/Unitroller.sol) | 64 | This contract delegate calls most actions to the Comptroller and acts as the storage proxy | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [src/core/Governance/TemporalGovernor.sol](src/core/Governance/TemporalGovernor.sol) | 248 | This contract governs the Base deployment of Moonwell through actions submitted through Wormhole | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [src/core/MToken.sol](src/core/MToken.sol) | 693 | Abstract base for MTokens | none |
| [src/core/MErc20.sol](src/core/MErc20.sol) | 112 | Moonwell MERC20 Token Contract | none |
| [src/core/MErc20Delegator.sol](src/core/MErc20Delegator.sol) | 212 | Moonwell Delegator Contract | none |
| [src/core/MErc20Delegate.sol](src/core/MErc20Delegate.sol) | 18 | Moonwell Delegate Contract, delegate-called by delegator | none |
| [src/core/router/WETHRouter.sol](src/core/router/WETHRouter.sol) | 40 | Mint and redeem MTokens for raw ETH |  [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |
| [src/core/IRModels/InterestRateModel.sol](src/core/IRModels/InterestRateModel.sol) | 6 | Interface for interest rate models | none |
| [src/core/IRModels/WhitePaperInterestRateModel.sol](src/core/IRModels/WhitePaperInterestRateModel.sol) | 31 | White paper interest rate model  | none |
| [src/core/IRModels/JumpRateModel.sol](src/core/IRModels/JumpRateModel.sol) | 41 | Jump rate interest rate model, rates spike after kink  | none |
| [src/core/Oracles/ChainlinkCompositeOracle.sol](src/core/Oracles/ChainlinkCompositeOracle.sol) | 138 | Chainlink composite oracle, combines 2 or 3 chainlink oracle feeds into a single composite price  | none |
| [src/core/Oracles/ChainlinkOracle.sol](src/core/Oracles/ChainlinkOracle.sol) | 109 | Stores all chainlink oracle addresses for each respective underlying asset  | none |
| [test/proposals/mips/mip00.sol](test/proposals/mips/mip00.sol) | 586 | Handles deployment and parameterization of initial system  | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |

## Out of scope

* All files in the [deprecated](src/core/Governance/deprecated/) folder are out of scope
* All files in the [mock](test/mock/) folder are out of scope
* [Safemath](src/core/SafeMath.sol)
* All openzeppelin dependencies

# Additional Context

*Describe any novel or unique curve logic or mathematical models implemented in the contracts*

*Sponsor, please confirm/edit the information below.*

## Scoping Details 
```
- If you have a public code repo, please share it here:  
- How many contracts are in scope?:   12
- Total SLoC for these contracts?:  4802
- How many external imports are there?:  1
- How many separate interfaces and struct definitions are there for the contracts within scope?:  22 structs, 9 interfaces
- Does most of your code generally use composition or inheritance?:   Inheritance
- How many external calls?:  3 
- What is the overall line coverage percentage provided by your tests?: 80%
- Is this an upgrade of an existing system?: True; Compound with multi-reward contract to handle distributing rewards in multiple assets per cToken, plus a cross chain governance system as well as a WETHRouter to allow users to go into mETH without having the protocol natively handle ETH.
- Check all that apply (e.g. timelock, NFT, AMM, ERC20, rollups, etc.): Multi-Chain, ERC-20 Token, Timelock function
- Is there a need to understand a separate part of the codebase / get context in order to audit this part of the protocol?:   True
- Please describe required context:   Understand governance system on moonbeam to figure out how temporal governance works
- Does it use an oracle?:  No
- Describe any novel or unique curve logic or mathematical models your code uses: n/a
- Is this either a fork of or an alternate implementation of another project?:   True; Compound with MRD
- Does it use a side-chain?: False
- Describe any specific areas you would like addressed: Would like to see people try to break the MRD logic, the temporal governor, the weth router, and take a deep look at the deployment script for any possible misconfigurations of the system. also any issues with calls to MRD from other parts of the system enabling theft of rewards or claiming of rewards that users aren't entitled to
```

# Tests

*Provide every step required to build the project from a fresh git clone, as well as steps to run the tests with a gas report.* 

*Note: Many wardens run Slither as a first pass for testing.  Please document any known errors with no workaround.* 

# Moonwell Protocol v2

The Moonwell Protocol is a fork of Benqi, which is a fork of Compound v2 with things like borrow caps and multi-token
emissions. 

The "v2" release of the Moonwell Protocol is a major system upgrade to use solidity 0.8.17, add supply caps, and a number
of improvements for user experience (things like `mintWithPermit` and `claimAllRewards`). Solidity version 0.8.20 was not used because EIP-3855 which adds the PUSH0 opcode will not be live on base where this system will be deployed.

# Running + Development

Development will work with the latest version of foundry installed.

Basic development workflow:
- use `forge build` to build the smart contracts
- use `forge test -vvv --match-contract UnitTest` to run the unit tests
- use `forge test --match-contract IntegrationTest --fork-url $ETH_RPC_URL` to run the integration tests
- use `forge test --match-contract ArbitrumTest --fork-url $ARB_RPC_URL` to run the ChainlinkCompositeOracle tests
- use `forge script test/proposals/DeployProposal.s.sol:DeployProposal -vvvv --rpc-url $ETH_RPC_URL` to do a dry run of the deployment script


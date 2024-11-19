# MIP-B35: Create USDC Reward Stream on cbBTC Market and Assign Gauntlet as Emissions Admin

## Summary

This proposal seeks to initiate USDC incentives on Moonwell's cbBTC market on
Base. Gauntlet will also be assigned as the Emissions Admin to dynamically
manage USDC rewards on this market without requiring further governance
proposals. For this initial four week period, 80,000 USDC will be transferred to
the
[MultiRewardDistributor contract](https://basescan.org/address/0xe9005b078701e2A0948D2EaC43010D35870Ad9d2)
and the execution of this proposal will initiate rewards.

## Proposal Actions

The following actions will be executed as part of this proposal:

1. **Create USDC Reward Stream and Assign Admin Role:** Establish a new USDC
   reward stream for the cbBTC market, with Gauntlet as the Emissions Admin by
   calling `_updateOwner` on the MultiRewardDistributor contract:

   - **mToken:**
     [0xF877ACaFA28c19b96727966690b2f44d35aD5976](https://basescan.org/address/0xf877acafa28c19b96727966690b2f44d35ad5976)
   - **emissionToken:**
     [0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913](https://basescan.org/address/0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913)
   - **newOwner:**
     [0x5a4E19842e09000a582c20A4f524C26Fb48Dd4D0](https://basescan.org/address/0x5a4e19842e09000a582c20a4f524c26fb48dd4d0)
     (Gauntlet)

2. **Set Supply Reward Speed for cbBTC Market:**

   - Set supply speed to **33068** rewards per second for suppliers by calling
     `_updateSupplySpeed` on the MultiRewardDistributor contract.

3. **Update Emissions End Time:** Configures the reward stream duration by
   setting the end timestamp on the MultiRewardDistributor contract:
   - **newEndTime:** 1733241600 (December 03 2024 16:00 GMT)

## Rationale

- **USDC Incentives on cbBTC Market:** This proposal will initiate USDC rewards
  for the cbBTC market on Base. These incentives are aimed at boosting liquidity
  and usage of the cbBTC market on Moonwell.
- **Gauntlet as Emissions Admin:** By assigning Gauntlet control over USDC
  emissions, the protocol can benefit from their expertise in optimizing
  incentive distribution dynamically, reducing the need for further governance
  actions.

## Voting Options

- **Aye:** Approve the creation of a USDC reward stream on the cbBTC market,
  assign Gauntlet as Emissions Admin, set the reward speeds, and define the
  emission end time.
- **Nay:** Reject the proposal and maintain the current incentive structure.
- **Abstain:** Abstain from voting on this proposal.

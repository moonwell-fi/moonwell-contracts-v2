# MIP-B33: Initiating USDC rewards and Assigning Gauntlet as USDC Emissions Admin

## Summary
This proposal seeks to initiate USDC incentives on Moonwell's USDC market on Base. Gauntlet will also be assigned as the USDC Emissions Admin to dynamically manage these rewards without requiring further governance proposals. For this initial period, 50,000 USDC will be transferred to the [MultiRewardDistributor](https://basescan.org/address/0xe9005b078701e2A0948D2EaC43010D35870Ad9d2) contract, and the execution of this proposal will initiate rewards, setting speeds equally across both supply and borrow.

## Proposal Actions
The following actions will be executed as part of this proposal:

1. **Update Admin Role**
   Call `_updateOwner` on the MultiRewardDistributor, specifically for the USDC market:
   - **mToken**: 0xEdc817A28E8B93B03976FBd4a3dDBc9f7D176c22 (Moonwell USDC)
   - **emissionToken**: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913 (USDC)
   - **newOwner**: 0x5a4E19842e09000a582c20A4f524C26Fb48Dd4D0 (Gauntlet)

2. **Update Supply Speed**
   Call `_updateSupplySpeed` on the MultiRewardDistributor for the USDC market:
   - **newSupplySpeed**: 13,778

3. **Update Borrow Speed**
   Call `_updateBorrowSpeed` on the MultiRewardDistributor for the USDC market:
   - **newBorrowSpeed**: 13,778

4. **Update Emissions End Time**
   Call `_updateEndTime` on the MultiRewardDistributor for the USDC market:
   - **newEndTime**: 1731081600 (Friday, November 8, 2024, 16:00 GMT)

## Rationale
- **USDC Incentives**: This proposal will initiate USDC rewards for the USDC market on Base by setting the reward speeds for both suppliers and borrowers. These incentives are aimed at boosting liquidity and usage of the USDC market on Moonwell.
- **Gauntlet as Emissions Admin**: By assigning Gauntlet control over USDC emissions, the protocol can benefit from their expertise in optimizing incentive distribution dynamically, reducing the need for further governance actions.
- **Supply and Borrow Speeds**: The reward speeds of 13,778 for both suppliers and borrowers help ensure an equitable distribution of incentives across market participants and should drive increased borrowing demand.

## Voting Options
- **Aye**: Approve the proposal to assign Gauntlet as emissions admin, update supply and borrow speeds, and set the emissions end time.
- **Nay**: Reject the proposal and maintain the current emissions structure.
- **Abstain**: Abstain from voting on this proposal.
(edited)
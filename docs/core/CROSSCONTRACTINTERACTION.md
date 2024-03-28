# Overview

This document provides an in depth look into how the contracts will call each
other during each user action.

## Mint

When a user calls the `mint` function on the MToken, it will call the
`mintAllowed` function on the Comptroller. If the mint is allowed, then
`updateMarketSupplyIndexAndDisburseSupplierRewards` on the
MultiRewardDistributor contract is called, which then updates the supply reward
index on the the MultiRewardDistributor. Then, the user individual rewards is
updated by calling the MToken `balanceOf` function, figuring out how much tokens
a user had for what duration, and then calculating the amount of rewards they
have accrued.

Summarizing the interactions that occur when a user calls mint:
`MToken -> Comptroller -> MultiRewardDistributor -> MToken`

## Borrow

When a user calls the `borrow` function on the MToken, it will call the
`borrowAllowed` function on the Comptroller. If the borrow is allowed, then
`updateMarketBorrowIndexAndDisburseBorrowerRewards` on the
MultiRewardDistributor contract is called, which then updates the supply reward
index on the MultiRewardDistributor. Then, the user individual rewards is
updated by calling the MToken `borrowBalanceStored` function, figuring out how
much tokens a user had borrowed for what duration, and then calculating the
amount of rewards they have accrued for initiating that borrow.

Summarizing the interactions that occur when a user calls borrow:
`MToken -> Comptroller -> MultiRewardDistributor -> MToken`

# MErc20Delegator

## Overview

The MErc20Delegator delegate calls into the MErc20Delegate contract. This allows the implementation to be upgraded at a future point in time if needed.

Summary of Functions and Events in the MErc20Delegator Contract:

1. Constructor:
   - Initializes the MErc20Delegator contract with the provided parameters.
   - Sets the admin as the contract creator during initialization.
   - Calls the "initialize" function on the implementation contract with the provided parameters.
   - Sets the new implementation address.
   - Sets the proper admin after initialization.

2. _setImplementation:
   - Called by the admin to update the implementation of the delegator contract.
   - If "allowResign" is true, it calls "_resignImplementation" on the old implementation.
   - Updates the implementation address to the new implementation provided.
   - Calls "_becomeImplementation" on the new implementation with the provided "becomeImplementationData".
   - Emits a "NewImplementation" event.

3. mint:
   - Sender supplies assets into the market and receives mTokens in exchange.
   - Accrues interest regardless of the operation's success.

4. mintWithPermit:
   - Supply assets without a 2-step approval process using EIP-2612 permit.
   - Calls the underlying token's "permit()" function and assumes success.

5. redeem:
   - Sender redeems mTokens in exchange for the underlying asset.
   - Accrues interest regardless of the operation's success.

6. redeemUnderlying:
   - Sender redeems mTokens for a specified amount of underlying asset.
   - Accrues interest regardless of the operation's success.

7. borrow:
   - Sender borrows assets from the protocol to their own address.

8. repayBorrow:
   - Sender repays their own borrow.

9. repayBorrowBehalf:
   - Sender repays a borrow on behalf of another borrower.

10. liquidateBorrow:
    - Sender liquidates a borrower's collateral, transferring it to the liquidator.

11. transfer:
    - Transfer `amount` mTokens from `msg.sender` to `dst`.

12. transferFrom:
    - Transfer `amount` mTokens from `src` to `dst` with approval.

13. approve:
    - Approve `spender` to transfer up to `amount` from `msg.sender`.

14. allowance:
    - Get the current allowance from `owner` for `spender`.

15. balanceOf:
    - Get the mToken balance of the `owner`.

16. balanceOfUnderlying:
    - Get the underlying balance of the `owner`, accruing interest.

17. getAccountSnapshot:
    - Get a snapshot of the account's balances and the cached exchange rate.

18. borrowRatePerTimestamp:
    - Returns the current per-timestamp borrow interest rate for this mToken.

19. supplyRatePerTimestamp:
    - Returns the current per-timestamp supply interest rate for this mToken.

20. totalBorrowsCurrent:
    - Returns the current total borrows plus accrued interest.

21. borrowBalanceCurrent:
    - Accrue interest to the updated borrowIndex and calculate the account's borrow balance.

22. borrowBalanceStored:
    - Return the borrow balance of an account based on stored data.

23. exchangeRateCurrent:
    - Accrue interest and return the up-to-date exchange rate.

24. exchangeRateStored:
    - Calculate the exchange rate from the underlying to the mToken without accruing interest.

25. getCash:
    - Get the cash balance of this mToken in the underlying asset.

26. accrueInterest:
    - Apply accrued interest to total borrows and reserves.

27. seize:
    - Transfer collateral tokens (this market) to the liquidator during liquidation.

28. sweepToken:
    - Sweep accidental ERC-20 transfers to this contract to the admin (timelock).
    - callable only by the admin

29. Admin Functions:
    - _setPendingAdmin: Begins the transfer of admin rights.
    - _setComptroller: Sets a new comptroller for the market.
    - _setReserveFactor: Accrues interest and sets a new reserve factor for the protocol.
    - _acceptAdmin: Accepts transfer of admin rights.
    - _addReserves: Accrues interest and adds reserves by transferring from admin.
    - _reduceReserves: Accrues interest and reduces reserves by transferring to admin.
    - _setInterestRateModel: Accrues interest and updates the interest rate model.
    - _setProtocolSeizeShare: Accrues interest and sets a new protocol seize share.

30. Delegate Functions:
    - delegateTo: Internal method to delegate execution to another contract.
    - delegateToImplementation: Delegates execution to the implementation contract.
    - delegateToViewImplementation: Delegates execution to an implementation contract with view functions.

31. Fallback Function:
    - Delegates all other functions to the current implementation contract.
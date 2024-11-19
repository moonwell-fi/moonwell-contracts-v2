# MIP-B02: Moonwell WETH Market Improvement

## Summary

MIP-B02 is a strategic proposal that is designed to enhance the user experience
for those utilizing the WETH market on Moonwell's Base deployment. Currently,
those borrowing ETH on Moonwell (Base) receive Wrapped ETH (WETH), with
repayments also requiring the usage of WETH. This results in a suboptimal user
experience, as borrowers must unwrap their borrowed WETH before utilizing it in
the Base ecosystem, and those repaying active borrows need to rewrap their ETH
before being able to do so. The primary objective of this proposal is to
streamline these processes to ensure borrowers directly receive native ETH,
thereby eliminating the need for manual unwrapping, and also to allow for
repayments to be made in ETH, as opposed to WETH.

## Motivation

This proposal aims to improve the UX for those engaging with the WETH market on
Moonwell's Base deployment. These proposed upgrades bring about several key
advantages for end users:

1. **Borrows and repayments in native ETH:** Borrowers, individuals redeeming
   their mTokens, and those reducing reserves within the Moonwell WETH market
   will now be able to directly receive or repay borrows in raw ETH as part of
   their transaction process.
2. **Integrated WETH Unwrapping:** The WETHUnwrapper contract's straightforward
   functionality ensures that the process of converting wrapped WETH into raw
   ETH is efficient and transparent. This ETH is then distributed to the
   relevant end user.

## Implementation Details

Various smart contracts will be deployed as part of and alongside this proposal:

1. **MWETHDelegate Contract:** This upgrade changes the logic contract for the
   WETH market to an MWETHDelegate contract. This contract's primary function is
   to facilitate interactions with the new WETHUnwrapper contract, thereby
   enabling streamlined operations and improved user experience.
2. **WETHUnwrapper Contract:** A dedicated WETHUnwrapper contract will be
   deployed as part of this proposal. The WETHUnwrapper contract is a simple
   smart contract deployed on Base that the MWETHDelegate contract sends WETH to
   and then calls unwrap, which converts the WETH into raw ETH and is then
   directed to the respective user.
3. **WETHRouter Contract:** Adjacent to this proposal, a new WETHRouter smart
   contract will replace the currently deployed version. This upgraded
   WETHRouter contract will empower users to repay active borrows directly in
   ETH, bypassing the need for manual wrapping into WETH. All new smart
   contracts associated with MIP-B02 have been audited by Moonwell contributors
   at Halborn Security. Halborn's latest audit report can be found
   [here](https://docs.moonwell.fi/moonwell/protocol-information/audits).

## Voting Options

- **Yes:** A "Yes" vote signifies your support for the implementation of
  MIP-B02.
- **No:** A "No" vote indicates your preference for the status quo, no changes
  should be made.

## Conclusion

In summary, MIP-B02 is a proposal that will dramatically enhance the UX for
those borrowing ETH on Moonwell. By deploying the new MWETHDelegate and
WETHUnwrapper smart contracts, this proposal facilitates direct ETH borrows and
repayments for end users and abstracts away the process of converting wrapped
WETH into raw ETH. Your support for MIP-B02 will play a pivotal role in
enhancing the overall user experience and convenience of borrowing and repaying
ETH on Moonwell's Base deployment.

# MIP-M24: Multichain Governor Migration - Accept Ownership as Multichain Governor

## Overview

MIP-M24 represents the final step in Moonwell's transition to a multichain governance model, building upon the
groundwork laid by MIP-M23. This proposal focuses on the new multichain governor accepting governance powers, completing
the transfer of admin and ownership roles from the current governor. Additionally, this proposal will remove the
Timelock contract as a trusted sender on the temporal governor contract on Base. By finalizing this migration, the
Moonwell community will be fully equipped to leverage the benefits of cross-chain governance, enhancing scalability and
enabling governance participation across all supported networks.

## Implementation

To complete the migration to the new multichain governor, the following onchain actions will be executed as part of this
proposal:

-   Accept pending admin of all mToken contracts
-   Accept pending admin of the Comptroller
-   Accept Wormhole Bridge Adapter ownership
-   Accept xWELL ownership
-   Remove old Timelock as a trusted sender on the temporal governor

After initiating the contract ownership changes in MIP-M23, it is crucial to finalize ownership transfer to the new
multichain governor. By accepting the pending admin and ownership roles for the mToken contracts, Comptroller, Wormhole
Bridge Adapter, and xWELL contract, the multichain governor will be fully empowered to manage the protocol's core
components

## Conclusion

The successful implementation of MIP-M24 will mark the culmination of Moonwell's transition to a multichain governance
model. By finalizing the transfer of ownership and admin roles to the new multichain governor contract, the Moonwell
community will be empowered to participate in the protocol's governance directly from Base or any other future network,
without the need for bridging tokens or navigating complex cross-chain processes. This milestone represents a
significant step forward in Moonwell's evolution, demonstrating the community’s commitment to long-term sustainability
and pushing the boundaries of what is possible in onchain governance.

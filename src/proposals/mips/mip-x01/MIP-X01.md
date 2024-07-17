# MIP-X01 - Cross Chain WELL Activation and System Upgrade

This governance proposal enables the WELL token to be activated on Optimism and
performs the necessary steps to enable the token to be transferred across
networks. This proposal also adds the Multichain Vote Collection contract on
Optimism as a trusted sender on Moonbeam, allowing the WELL token to participate
in governance on Optimism and ensuring new proposals are broadcast to this
chain. Additionally, this upgrades the Multichain Governor on Moonbeam and the
Vote Collection contract on Base to refund excess native tokens when proposing,
or emitting votes.

This governance proposal also upgrades the WELL token implementation on both
Base and Moonbeam to allow the owner the ability to unpause the contracts. This
means that following a successful governance proposal, the community can vote to
unpause the xWELL token if the guardian has previously paused it.

These changes were unit and integration tested, audited by Halborn, reviewed by
a Solidity Labs engineer, and had the formal proofs run again, demonstrating the
safety of the code change.

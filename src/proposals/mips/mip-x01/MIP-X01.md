# MIP-X01 - Cross Chain WELL Activation and System Upgrade

This governance proposal enables the WELL token to be activated on Optimism and
performs the necessary steps to enable the token to be transferred across
networks. Additionally, this upgrades the Multichain Governor and the Vote
Collection contract to refund excess native tokens when proposing, or emitting
votes.

This governance proposal also upgrades the WELL token implementation to allow
the owner the ability to unpause the contracts. This means that following a
successful governance proposal, the community can vote to unpause the xWELL
token if the guardian has previously paused it.

These changes were audited by Halborn, reviewed by a Solidity Labs engineer, and
had the formal proofs run again, demonstrating the safety of the code change.

# MIP-M30: Multichain Governor Migration - Transfer wBTC market admin

During the Multichain Governor Migration on proposal MIP-M23, there was an
oversight in transferring the wBTC market admin. Although the Solidity Labs team
conducted a thorough line-by-line review of MIP-M23 and the MIP also underwent
an external audit, the Addresses.json file pointed to the deprecated wBTC
market. As a result, only the deprecated market (wBTC mad) was transferred,
while the actual market was not.

The purpose of this proposal is to transfer the wBTC market admin to the new
Multichain Governor. To prevent similar issues in the future, the Solidity Labs
engineers will ensure that all addresses saved in the Addresses.json file have
their corresponding names, and that all deprecated markets are clearly labeled
as "DEPRECATED" before the name.

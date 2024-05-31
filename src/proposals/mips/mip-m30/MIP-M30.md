# MIP-M30: Multichain Governor Migration - Transfer wBTC market admin

During the Multichain Governor Migration on proposal MIP-M23, there was an
oversight in transferring the wBTC market admin. Although the Solidity Labs team
conducted a thorough line-by-line review of MIP-M23 and the MIP also underwent
an external audit, the Addresses.json file pointed to the deprecated wBTC
market. As a result, only the deprecated market (wBTC mad) was transferred,
while the actual market was not.

The purpose of this proposal is to transfer the wBTC market admin to the new
Multichain Governor. To enhance our processes and prevent similar issues in the
future, an internal review will be conduct. This will likely include updating
the naming conventions for addresses.

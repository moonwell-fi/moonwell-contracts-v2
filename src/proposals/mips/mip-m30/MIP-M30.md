# MIP-M30: Multichain Governor Migration - Transfer wBTC market admin

Unfortunately, during the Multichain Governor Migration on proposal MIP-M23,
there was an oversight in transferring the wBTC market admin. The purpose of
this proposal is to transfer the wBTC market admin to the new Multichain
Governor. To prevent similar issues in the future, Solidity Labs engineers will
thoroughly review the tooling to ensure that all addresses saved in the
Addresses.json file have their corresponding names and that all deprecated
markets are properly labeled with "DEPRECATED" before the name.

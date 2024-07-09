# MIP-M30: Multichain Governor Migration - Transfer wBTC market admin

MIP-M23 was the starting point for the Governance migration for the new cross-chain contracts. This involved several
crucial steps for the ratification of Cross-Chain Governance within the Moonwell contracts on the Base and Moonbeam
networks. Among these steps was the transfer of admin privileges of the Moonwell Markets on Moonbeam to the new
Governor. During MIP-M23, we successfully transferred the admin privileges of BUSD, WETH, USDC, GLIMMER, DOT, FRAX, and
WBTC with the DAO approval. However, two WBTC markets needed to be transferred, and only one transfer was made on
MIP-M23. This proposal transfers the admin privileges of the remaining WBTC market to the new Multichain Governor.
Despite a comprehensive line-by-line review of MIP-M23 by the Solidity Labs team and an external audit, the initial
specification did not include this missing transfer. Therefore, this proposal is necessary.

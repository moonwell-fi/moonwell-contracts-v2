//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

uint256 constant MOONBEAM_FORK_ID = 0;
uint256 constant BASE_FORK_ID = 1;
uint256 constant OPTIMISM_FORK_ID = 2;

uint256 constant MOONBEAM_CHAIN_ID = 1284;
uint256 constant BASE_CHAIN_ID = 8453;
uint256 constant OPTIMISM_CHAIN_ID = 10;

uint256 constant MOONBASE_CHAIN_ID = 1287;
uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;
uint256 constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;

library ChainIds {
    function toForkId(uint256 chainId) internal pure returns (uint256) {
        if (chainId == MOONBEAM_CHAIN_ID || chainId == MOONBASE_CHAIN_ID) {
            return MOONBEAM_FORK_ID;
        } else if (
            chainId == BASE_CHAIN_ID || chainId == BASE_SEPOLIA_CHAIN_ID
        ) {
            return BASE_FORK_ID;
        } else if (
            chainId == OPTIMISM_CHAIN_ID || chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            return OPTIMISM_FORK_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }
}

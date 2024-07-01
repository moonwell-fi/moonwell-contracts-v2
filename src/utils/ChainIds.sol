//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Vm} from "@forge-std/Vm.sol";
// Fork Ids
uint256 constant MOONBEAM_FORK_ID = 0;
uint256 constant BASE_FORK_ID = 1;
uint256 constant OPTIMISM_FORK_ID = 2;

// Mainnet Chain Ids
uint256 constant MOONBEAM_CHAIN_ID = 1284;
uint256 constant BASE_CHAIN_ID = 8453;
uint256 constant OPTIMISM_CHAIN_ID = 10;

uint256 constant LOCAL_CHAIN_ID = 31337;

// Testnet Chain Ids
uint256 constant MOONBASE_CHAIN_ID = 1287;
uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;
uint256 constant OPTIMISM_SEPOLIA_CHAIN_ID = 11155420;

// Wormhole Mainnet Chain Ids
uint16 constant MOONBEAM_WORMHOLE_CHAIN_ID = 16;
uint16 constant BASE_WORMHOLE_CHAIN_ID = 30;
uint16 constant OPTIMISM_WORMHOLE_CHAIN_ID = 24;

// Wormhole Testnet Chain Ids
uint16 constant MOONBASE_WORMHOLE_CHAIN_ID = 16;
uint16 constant BASE_WORMHOLE_SEPOLIA_CHAIN_ID = 10004;
uint16 constant OPTIMISM_WORMHOLE_SEPOLIA_CHAIN_ID = 10005;

library ChainIds {
    address internal constant CHEATCODE_ADDRESS =
        0x7109709ECfa91a80626fF3989D68f67F5b1DD12D;
    Vm internal constant vmInternal = Vm(CHEATCODE_ADDRESS);

    function toMoonbeamChainId(
        uint256 chainId
    ) internal pure returns (uint256) {
        if (chainId == BASE_CHAIN_ID || chainId == OPTIMISM_CHAIN_ID) {
            return MOONBEAM_CHAIN_ID;
        } else if (
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            return MOONBASE_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toMoonbeamWormholeChainId(
        uint256 chainId
    ) internal pure returns (uint256) {
        if (chainId == BASE_CHAIN_ID || chainId == OPTIMISM_CHAIN_ID) {
            return MOONBEAM_WORMHOLE_CHAIN_ID;
        } else if (
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            return MOONBASE_WORMHOLE_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toBaseWormholeChainId(
        uint256 chainId
    ) internal pure returns (uint256) {
        if (chainId == MOONBEAM_CHAIN_ID) {
            return BASE_WORMHOLE_CHAIN_ID;
        } else if (chainId == MOONBASE_CHAIN_ID) {
            return BASE_WORMHOLE_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toBaseChainId(uint256 chainId) internal pure returns (uint256) {
        if (chainId == MOONBEAM_CHAIN_ID) {
            return BASE_CHAIN_ID;
        } else if (chainId == MOONBASE_CHAIN_ID) {
            return BASE_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toOptimismChainId(
        uint256 chainId
    ) internal pure returns (uint256) {
        if (chainId == MOONBEAM_CHAIN_ID) {
            return OPTIMISM_CHAIN_ID;
        } else if (chainId == MOONBASE_CHAIN_ID) {
            return OPTIMISM_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

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

    function checkForks(uint256 forkId) internal {
        require(
            forkId == MOONBEAM_FORK_ID ||
                forkId == BASE_FORK_ID ||
                forkId == OPTIMISM_FORK_ID,
            "ChainIds: invalid fork id"
        );

        if (forkId == MOONBEAM_FORK_ID) {
            require(
                vmInternal.activeFork() == MOONBEAM_FORK_ID,
                "ChainIds: invalid active fork"
            );

            // all other forks must also be mainnet
            if (block.chainid == MOONBEAM_CHAIN_ID) {
                vmInternal.selectFork(BASE_FORK_ID);

                require(
                    block.chainid == BASE_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(OPTIMISM_FORK_ID);

                require(
                    block.chainid == OPTIMISM_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else if (block.chainid == MOONBASE_CHAIN_ID) {
                vmInternal.selectFork(BASE_FORK_ID);

                require(
                    block.chainid == BASE_SEPOLIA_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(OPTIMISM_FORK_ID);

                require(
                    block.chainid == OPTIMISM_SEPOLIA_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else {
                revert("ChainIds: invalid RPC URL");
            }
        } else if (forkId == BASE_FORK_ID) {
            require(
                vmInternal.activeFork() == BASE_FORK_ID,
                "ChainIds: invalid active fork"
            );

            // all other forks must also be mainnet
            if (block.chainid == BASE_CHAIN_ID) {
                vmInternal.selectFork(MOONBEAM_FORK_ID);

                require(
                    block.chainid == MOONBEAM_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(OPTIMISM_FORK_ID);

                require(
                    block.chainid == OPTIMISM_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else if (block.chainid == BASE_SEPOLIA_CHAIN_ID) {
                vmInternal.selectFork(MOONBASE_CHAIN_ID);

                require(
                    block.chainid == MOONBASE_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(OPTIMISM_FORK_ID);

                require(
                    block.chainid == OPTIMISM_SEPOLIA_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else {
                revert("ChainIds: invalid RPC URL");
            }
        } else if (forkId == OPTIMISM_FORK_ID) {
            require(
                vmInternal.activeFork() == OPTIMISM_FORK_ID,
                "ChainIds: invalid active fork"
            );

            // all other forks must also be mainnet
            if (block.chainid == OPTIMISM_CHAIN_ID) {
                vmInternal.selectFork(MOONBEAM_FORK_ID);

                require(
                    block.chainid == MOONBEAM_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(BASE_FORK_ID);

                require(
                    block.chainid == BASE_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else if (block.chainid == OPTIMISM_SEPOLIA_CHAIN_ID) {
                vmInternal.selectFork(MOONBASE_CHAIN_ID);

                require(
                    block.chainid == MOONBASE_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );

                vmInternal.selectFork(BASE_FORK_ID);

                require(
                    block.chainid == BASE_SEPOLIA_CHAIN_ID,
                    "ChainIds: invalid chain id"
                );
            } else {
                revert("ChainIds: invalid RPC URL");
            }
        }

        // switch back to the original fork
        vmInternal.selectFork(forkId);
    }

    function createForksAndSelect(uint256 selectFork) internal {
        vmInternal.createFork(vmInternal.envString("MOONBEAM_RPC_URL"));
        vmInternal.createFork(vmInternal.envString("BASE_RPC_URL"));
        vmInternal.createFork(vmInternal.envString("OP_RPC_URL"));

        vmInternal.selectFork(selectFork);

        checkForks(selectFork);
    }

    function toWormholeChainId(uint256 chainId) internal pure returns (uint16) {
        if (chainId == MOONBEAM_CHAIN_ID) {
            return MOONBEAM_WORMHOLE_CHAIN_ID;
        } else if (chainId == BASE_CHAIN_ID) {
            return BASE_WORMHOLE_CHAIN_ID;
        } else if (chainId == OPTIMISM_CHAIN_ID) {
            return OPTIMISM_WORMHOLE_CHAIN_ID;
        } else if (chainId == MOONBASE_CHAIN_ID) {
            return MOONBASE_WORMHOLE_CHAIN_ID;
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID) {
            return BASE_WORMHOLE_SEPOLIA_CHAIN_ID;
        } else if (chainId == OPTIMISM_SEPOLIA_CHAIN_ID) {
            return OPTIMISM_WORMHOLE_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }
}

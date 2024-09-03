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
uint16 constant ETHEREUM_WORMHOLE_CHAIN_ID = 2;

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
        /// map mainnet base, optimism and moonbeam chain id to moonbeam chain id
        if (
            chainId == BASE_CHAIN_ID ||
            chainId == OPTIMISM_CHAIN_ID ||
            chainId == MOONBEAM_CHAIN_ID
        ) {
            return MOONBEAM_CHAIN_ID;
        } else if (
            chainId == MOONBASE_CHAIN_ID ||
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            /// map base sepolia, optimism sepolia and moonbase chain id to moonbase chain id
            return MOONBASE_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id to moonbeam chain id");
        }
    }

    function toBaseChainId(uint256 chainId) internal pure returns (uint256) {
        /// map base and moonbeam chain id to base chain id
        if (
            chainId == OPTIMISM_CHAIN_ID ||
            chainId == MOONBEAM_CHAIN_ID ||
            chainId == BASE_CHAIN_ID
        ) {
            return BASE_CHAIN_ID;
        } else if (
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID ||
            chainId == MOONBASE_CHAIN_ID ||
            chainId == BASE_SEPOLIA_CHAIN_ID
        ) {
            /// map base sepolia and moonbase chain id to base sepolia chain id
            return BASE_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id to base chain id");
        }
    }

    function toOptimismChainId(
        uint256 chainId
    ) internal pure returns (uint256) {
        /// map optimism and moonbeam chain id to optimism chain id
        if (
            chainId == MOONBEAM_CHAIN_ID ||
            chainId == OPTIMISM_CHAIN_ID ||
            chainId == BASE_CHAIN_ID
        ) {
            return OPTIMISM_CHAIN_ID;
        } else if (
            chainId == MOONBASE_CHAIN_ID ||
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            /// map optimism sepolia and moonbase chain id to optimism sepolia chain id
            return OPTIMISM_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id to optimism chain id");
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
        require(forkId <= OPTIMISM_FORK_ID, "ChainIds: invalid fork id");

        bool isMainnet = block.chainid == MOONBEAM_CHAIN_ID ||
            block.chainid == BASE_CHAIN_ID ||
            block.chainid == OPTIMISM_CHAIN_ID;

        if (isMainnet) {
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

            vmInternal.selectFork(OPTIMISM_FORK_ID);

            require(
                block.chainid == OPTIMISM_CHAIN_ID,
                "ChainIds: invalid chain id"
            );
        } else {
            vmInternal.selectFork(MOONBEAM_FORK_ID);

            require(
                block.chainid == MOONBASE_CHAIN_ID,
                "ChainIds: invalid chain id"
            );

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
        }
        // switch back to the original fork
        vmInternal.selectFork(forkId);
    }

    function createForksAndSelect(uint256 selectFork) internal {
        (bool success, ) = address(vmInternal).call(
            abi.encodeWithSignature("activeFork()")
        );
        (bool successSwitchFork, ) = address(vmInternal).call(
            abi.encodeWithSignature("selectFork(uint256)", selectFork)
        );

        if (!success || !successSwitchFork) {
            vmInternal.createFork(vmInternal.envString("MOONBEAM_RPC_URL"));
            vmInternal.createFork(vmInternal.envString("BASE_RPC_URL"));
            vmInternal.createFork(vmInternal.envString("OP_RPC_URL"));
        }

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

    function toMoonbeamWormholeChainId(
        uint256 chainId
    ) internal pure returns (uint16) {
        if (
            chainId == BASE_CHAIN_ID ||
            chainId == OPTIMISM_CHAIN_ID ||
            chainId == MOONBEAM_CHAIN_ID
        ) {
            return MOONBEAM_WORMHOLE_CHAIN_ID;
        } else if (
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID ||
            chainId == MOONBASE_CHAIN_ID
        ) {
            return MOONBASE_WORMHOLE_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toBaseWormholeChainId(
        uint256 chainId
    ) internal pure returns (uint16) {
        if (
            chainId == MOONBEAM_CHAIN_ID ||
            chainId == BASE_CHAIN_ID ||
            chainId == OPTIMISM_CHAIN_ID
        ) {
            return BASE_WORMHOLE_CHAIN_ID;
        } else if (
            chainId == MOONBASE_CHAIN_ID ||
            chainId == BASE_SEPOLIA_CHAIN_ID ||
            chainId == OPTIMISM_SEPOLIA_CHAIN_ID
        ) {
            return BASE_WORMHOLE_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function toChainId(
        uint256 wormholeChainId
    ) internal pure returns (uint256) {
        if (wormholeChainId == MOONBEAM_WORMHOLE_CHAIN_ID) {
            return MOONBEAM_CHAIN_ID;
        } else if (wormholeChainId == BASE_WORMHOLE_CHAIN_ID) {
            return BASE_CHAIN_ID;
        } else if (wormholeChainId == OPTIMISM_WORMHOLE_CHAIN_ID) {
            return OPTIMISM_CHAIN_ID;
        } else if (wormholeChainId == MOONBASE_WORMHOLE_CHAIN_ID) {
            return MOONBASE_CHAIN_ID;
        } else if (wormholeChainId == BASE_WORMHOLE_SEPOLIA_CHAIN_ID) {
            return BASE_SEPOLIA_CHAIN_ID;
        } else if (wormholeChainId == OPTIMISM_WORMHOLE_SEPOLIA_CHAIN_ID) {
            return OPTIMISM_SEPOLIA_CHAIN_ID;
        } else {
            revert("ChainIds: invalid wormhole chain id");
        }
    }

    function chainForkToName(
        uint256 forkId
    ) internal pure returns (string memory) {
        if (forkId == MOONBEAM_FORK_ID) {
            return "Moonbeam";
        } else if (forkId == BASE_FORK_ID) {
            return "Base";
        } else if (forkId == OPTIMISM_FORK_ID) {
            return "Optimism";
        } else {
            revert("ChainIds: invalid fork id");
        }
    }

    function chainIdToName(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == MOONBEAM_CHAIN_ID) {
            return "Moonbeam";
        } else if (chainId == BASE_CHAIN_ID) {
            return "Base";
        } else if (chainId == OPTIMISM_CHAIN_ID) {
            return "Optimism";
        } else if (chainId == MOONBASE_CHAIN_ID) {
            return "Moonbase";
        } else if (chainId == BASE_SEPOLIA_CHAIN_ID) {
            return "Base Sepolia";
        } else if (chainId == OPTIMISM_SEPOLIA_CHAIN_ID) {
            return "Optimism Sepolia";
        } else {
            revert("ChainIds: invalid chain id");
        }
    }

    function nonMoonbeamChainIds(uint256 chainId) internal pure returns (bool) {
        return chainId != MOONBEAM_CHAIN_ID && chainId != MOONBASE_CHAIN_ID;
    }
}

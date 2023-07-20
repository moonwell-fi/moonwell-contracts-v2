//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

contract ChainIds {
    /// ------------ BASE ------------

    uint256 public constant baseChainId = 84531;
    uint16 public constant baseWormholeChainId = 30; /// TODO update when actual base chain id is known
    
    uint256 public constant baseGoerliChainId = 84531;
    uint16 public constant baseGoerliWormholeChainId = 30;


    /// ------------ MOONBEAM ------------

    uint256 public constant moonBeamChainId = 1284;
    uint16 public constant moonBeamWormholeChainId = 16;

    uint256 public constant moonBaseChainId = 1287;
    uint16 public constant moonBaseWormholeChainId = 16;

    /// ------------ SEPOLIA ------------

    uint256 public constant sepoliaChainId = 11155111;
    uint16 public constant sepoliaWormholeChainId = 10002;

    /// ------------ GOERLI ------------

    uint256 public constant goerliChainId = 5;
    uint16 public constant goerliWormholeChainId = 2;

    /// @notice map a sending chain id to a wormhole chain id
    /// this way during a deployment, we can know which governance contract should own this deployment
    mapping (uint256 => uint16) public chainIdToWormHoleId;

    constructor() {
        chainIdToWormHoleId[sepoliaChainId] = goerliWormholeChainId; /// sepolia deployment is owned by goerli
        chainIdToWormHoleId[baseChainId] = moonBeamWormholeChainId; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[baseGoerliChainId] = moonBeamWormholeChainId; /// base deployment is owned by moonbeam governance
    }
}

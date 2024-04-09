//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

contract ChainIds {
    /// ------------ BASE ------------

    uint256 public constant baseChainId = 8453;
    uint16 public constant baseWormholeChainId = 30;

    uint256 public constant baseSepoliaChainId = 84532;
    uint16 public constant baseSepoliaWormholeChainId = 10004;

    /// ------------ MOONBEAM ------------

    uint256 public constant moonRiverChainId = 1285;

    uint256 public constant moonBeamChainId = 1284;
    uint16 public constant moonBeamWormholeChainId = 16;

    uint256 public constant moonBaseChainId = 1287;
    uint16 public constant moonBaseWormholeChainId = 16;

    /// ------------ SEPOLIA ------------

    uint256 public constant sepoliaChainId = 11155111;
    uint16 public constant sepoliaWormholeChainId = 10002;

    /// ------------ LOCAL ------------
    uint256 public constant localChainId = 31337;

    /// @notice map a sending chain id to a wormhole chain id
    /// this way during a deployment, we can know which governance contract should own this deployment
    mapping(uint256 => uint16) public chainIdToWormHoleId;

    /// @notice map a sending chain id to a receiving chainid so that we can create the correct calldata
    mapping(uint256 => uint256) public sendingChainIdToReceivingChainId;

    /// @notice map a chain id to a temporal gov timelock period
    mapping(uint256 => uint256) public chainIdTemporalGovTimelock;

    constructor() {
        chainIdToWormHoleId[baseSepoliaChainId] = moonBaseWormholeChainId; /// base deployment is owned by moonbeam governance

        chainIdToWormHoleId[baseChainId] = moonBeamWormholeChainId; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[moonBeamChainId] = baseWormholeChainId; /// moonbeam goes to base
        chainIdToWormHoleId[moonBaseChainId] = baseSepoliaWormholeChainId; /// moonbase goes to base
        sendingChainIdToReceivingChainId[baseSepoliaChainId] = moonBaseChainId; /// simulate a cross chain proposal by forking base testnet, and sending from moonbase testnet
        sendingChainIdToReceivingChainId[baseChainId] = moonBeamChainId; /// simulate a cross chain proposal by forking base, and sending from moonbeam
        sendingChainIdToReceivingChainId[moonBeamChainId] = baseChainId;

        sendingChainIdToReceivingChainId[moonBaseChainId] = baseSepoliaChainId;

        sendingChainIdToReceivingChainId[localChainId] = localChainId; // unit tests

        chainIdTemporalGovTimelock[baseSepoliaChainId] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[baseChainId] = 1 days;
    }
}

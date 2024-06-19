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

    /// ------------ OPTIMISM ------------

    uint256 public constant opChainId = 10;
    uint256 public constant opWormholeChainId = 24;

    uint256 public constant opSepoliaWormholeChainId = 10005;
    uint256 public constant opSepoliaChainId = 11155420;

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

        chainIdTemporalGovTimelock[baseSepoliaChainId] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[baseChainId] = 1 days;
    }

    function toMoonbeamChainId(uint256 chainId) public pure returns (uint256) {
        if (chainId == baseChainId) {
            return moonBeamChainId;
        } else if (chainId == baseSepoliaChainId) {
            return moonBaseChainId;
        } else if (chainId == opChainId) {
            return moonBeamChainId;
        } else if (chainId == opSepoliaChainId) {
            return moonBaseChainId;
        } else {
            revert("chain id not supported");
        }
    }

    function toBaseChainId(uint256 chainId) public pure returns (uint256) {
        if (chainId == moonBeamChainId) {
            return baseChainId;
        } else if (chainId == moonBaseChainId) {
            return baseSepoliaChainId;
        } else if (chainId == opChainId) {
            return baseChainId;
        } else if (chainId == opSepoliaChainId) {
            return baseSepoliaChainId;
        } else {
            revert("chain id not supported");
        }
    }

    function toOpChainId(uint256 chainId) public pure returns (uint256) {
        if (chainId == moonBeamChainId) {
            return opChainId;
        } else if (chainId == moonBaseChainId) {
            return opSepoliaChainId;
        } else if (chainId == baseChainId) {
            return opChainId;
        } else if (chainId == baseSepoliaChainId) {
            return opSepoliaChainId;
        } else {
            revert("chain id not supported");
        }
    }
}

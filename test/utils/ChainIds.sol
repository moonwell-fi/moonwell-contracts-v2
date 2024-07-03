//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@protocol/utils/Constants.sol";
import {ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

abstract contract ChainIds {
    /// @notice map a sending chain id to a wormhole chain id
    /// this way during a deployment, we can know which governance contract should own this deployment
    mapping(uint256 => uint16) public chainIdToWormHoleId;

    /// @notice map a sending chain id to a receiving chainid so that we can create the correct calldata
    mapping(uint256 => uint256) public sendingChainIdToReceivingChainId;

    /// @notice map a chain id to a temporal gov timelock period
    mapping(uint256 => uint256) public chainIdTemporalGovTimelock;

    mapping(uint256 => string) public chainForkToName;

    /// @notice a mapping of chain ids that are not moonbeam/moonbase chain ids
    mapping(uint256 => bool) public nonMoonbeamChainIds;

    constructor() {
        chainIdToWormHoleId[baseSepoliaChainId] = moonBaseWormholeChainId; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[optimismSepoliaChainId] = moonBaseWormholeChainId; /// optimism deployment is owned by moonbeam governance

        chainIdToWormHoleId[optimismChainId] = moonBeamWormholeChainId; /// optimism deployment is owned by moonbeam governance
        chainIdToWormHoleId[baseChainId] = moonBeamWormholeChainId; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[moonBeamChainId] = baseWormholeChainId; /// moonbeam goes to base
        chainIdToWormHoleId[moonBaseChainId] = baseSepoliaWormholeChainId; /// moonbase goes to base

        sendingChainIdToReceivingChainId[baseSepoliaChainId] = moonBaseChainId; /// simulate a cross chain proposal by forking base testnet, and sending from moonbase testnet
        sendingChainIdToReceivingChainId[moonBaseChainId] = baseSepoliaChainId;

        sendingChainIdToReceivingChainId[baseChainId] = moonBeamChainId; /// simulate a cross chain proposal by forking base, and sending from moonbeam
        sendingChainIdToReceivingChainId[moonBeamChainId] = baseChainId;

        sendingChainIdToReceivingChainId[optimismChainId] = moonBeamChainId; /// simulate a cross chain proposal by forking optimism, and sending from moonbeam

        sendingChainIdToReceivingChainId[
            optimismSepoliaChainId
        ] = moonBaseChainId; /// simulate a cross chain proposal by forking optimism testnet, and sending from moonbase testnet

        sendingChainIdToReceivingChainId[localChainId] = localChainId; // unit tests

        chainIdTemporalGovTimelock[baseSepoliaChainId] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[baseChainId] = 1 days;

        chainIdTemporalGovTimelock[optimismSepoliaChainId] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[optimismChainId] = 1 days;

        chainForkToName[uint256(ActionType.Moonbeam)] = "Moonbeam";
        chainForkToName[uint256(ActionType.Base)] = "Base";
        chainForkToName[uint256(ActionType.Optimism)] = "Optimism";

        nonMoonbeamChainIds[baseSepoliaChainId] = true;
        nonMoonbeamChainIds[baseChainId] = true;

        nonMoonbeamChainIds[optimismSepoliaChainId] = true;
        nonMoonbeamChainIds[optimismChainId] = true;
    }
}

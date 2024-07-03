//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {LOCAL_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBASE_CHAIN_ID, BASE_SEPOLIA_CHAIN_ID, OPTIMISM_SEPOLIA_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, MOONBASE_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_SEPOLIA_CHAIN_ID, OPTIMISM_WORMHOLE_SEPOLIA_CHAIN_ID, MOONBASE_WORMHOLE_CHAIN_ID} from "@protocol/utils/ChainIds.sol";

import {ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

abstract contract ChainIds {
    /// @notice map a sending chain id to a wormhole chain id
    /// this way during a deployment, we can know which governance contract should own this deployment
    mapping(uint256 => uint16) public chainIdToWormHoleId;

    /// @notice map a sending chain id to a receiving chainid so that we can create the correct calldata
    mapping(uint256 => uint256) public sendingChainIdToReceivingChainId;

    /// @notice map a chain id to a temporal gov timelock period
    mapping(uint256 => uint256) public chainIdTemporalGovTimelock;

    /// @notice allow logging of proposal type in HybridProposal
    mapping(uint256 => string) public chainForkToName;

    /// @notice a mapping of chain ids that are not moonbeam/moonbase chain ids
    mapping(uint256 => bool) public nonMoonbeamChainIds;

    constructor() {
        chainIdToWormHoleId[BASE_SEPOLIA_CHAIN_ID] = MOONBASE_WORMHOLE_CHAIN_ID; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[
            OPTIMISM_SEPOLIA_CHAIN_ID
        ] = MOONBASE_WORMHOLE_CHAIN_ID; /// optimism deployment is owned by moonbeam governance

        chainIdToWormHoleId[OPTIMISM_CHAIN_ID] = MOONBEAM_WORMHOLE_CHAIN_ID; /// optimism deployment is owned by moonbeam governance
        chainIdToWormHoleId[BASE_CHAIN_ID] = MOONBEAM_WORMHOLE_CHAIN_ID; /// base deployment is owned by moonbeam governance
        chainIdToWormHoleId[MOONBEAM_CHAIN_ID] = BASE_WORMHOLE_CHAIN_ID; /// moonbeam goes to base
        chainIdToWormHoleId[MOONBASE_CHAIN_ID] = BASE_WORMHOLE_SEPOLIA_CHAIN_ID; /// moonbase goes to base

        sendingChainIdToReceivingChainId[
            BASE_SEPOLIA_CHAIN_ID
        ] = MOONBASE_CHAIN_ID; /// simulate a cross chain proposal by forking base testnet, and sending from moonbase testnet
        sendingChainIdToReceivingChainId[
            MOONBASE_CHAIN_ID
        ] = BASE_SEPOLIA_CHAIN_ID;

        sendingChainIdToReceivingChainId[BASE_CHAIN_ID] = MOONBEAM_CHAIN_ID; /// simulate a cross chain proposal by forking base, and sending from moonbeam
        sendingChainIdToReceivingChainId[MOONBEAM_CHAIN_ID] = BASE_CHAIN_ID;

        sendingChainIdToReceivingChainId[OPTIMISM_CHAIN_ID] = MOONBEAM_CHAIN_ID; /// simulate a cross chain proposal by forking optimism, and sending from moonbeam

        sendingChainIdToReceivingChainId[
            OPTIMISM_SEPOLIA_CHAIN_ID
        ] = MOONBASE_CHAIN_ID; /// simulate a cross chain proposal by forking optimism testnet, and sending from moonbase testnet

        sendingChainIdToReceivingChainId[LOCAL_CHAIN_ID] = LOCAL_CHAIN_ID; // unit tests

        chainIdTemporalGovTimelock[BASE_SEPOLIA_CHAIN_ID] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[BASE_CHAIN_ID] = 1 days;

        chainIdTemporalGovTimelock[OPTIMISM_SEPOLIA_CHAIN_ID] = 0; /// no wait on testnet
        chainIdTemporalGovTimelock[OPTIMISM_CHAIN_ID] = 1 days;

        chainForkToName[uint256(ActionType.Moonbeam)] = "Moonbeam";
        chainForkToName[uint256(ActionType.Base)] = "Base";
        chainForkToName[uint256(ActionType.Optimism)] = "Optimism";

        nonMoonbeamChainIds[BASE_SEPOLIA_CHAIN_ID] = true;
        nonMoonbeamChainIds[BASE_CHAIN_ID] = true;

        nonMoonbeamChainIds[OPTIMISM_SEPOLIA_CHAIN_ID] = true;
        nonMoonbeamChainIds[OPTIMISM_CHAIN_ID] = true;
    }
}

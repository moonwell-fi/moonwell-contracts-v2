//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@protocol/utils/Constants.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {AddressToString} from "@protocol/xWELL/axelarInterfaces/AddressString.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

abstract contract ProposalChecker is ChainIds {
    using AddressToString for address;

    /// @notice should only be run while on the Moonbeam fork
    /// @dev checks that the Moonbeam actions do not include the Base wormhole core address and temporal governor address
    /// @param targets the list of targets for the Moonbeam actions
    /// @param addresses the addresses contract
    function checkMoonbeamActions(
        address[] memory targets,
        Addresses addresses
    ) public view {
        require(
            moonBeamChainId == block.chainid ||
                moonBaseChainId == block.chainid,
            "cannot run Moonbeam checks on non-Moonbeam network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            baseChainId
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            baseSepoliaChainId
        );

        address temporalGovBase = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            baseChainId
        );
        address temporalGovBaseSepolia = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            baseSepoliaChainId
        );

        for (uint256 i = 0; i < targets.length; i++) {
            /// there's no reason for any proposal actions to call addresses with 0 bytecode

            require(
                targets[i].code.length > 0,
                string(
                    abi.encodePacked(
                        "target for Moonbeam action not a contract ",
                        targets[i].toString()
                    )
                )
            );
            require(
                targets[i] != temporalGovBase,
                "Temporal Governor should not be in the list of targets for Moonbeam"
            );
            require(
                targets[i] != temporalGovBaseSepolia,
                "Temporal Governor Base Sepolia should not be in the list of targets for Moonbeam"
            );

            /// assert wormhole core BASE or BASE Sepolia address is not in the list of targets on Moonbeam
            require(
                targets[i] != wormholeCoreBase,
                "Wormhole Core Base should not be in the list of targets"
            );
            require(
                targets[i] != wormholeCoreBaseSepolia,
                "Wormhole Core Base Sepolia should not be in the list of targets"
            );
        }
    }

    /// @notice should only be run while on Base or Optimism mainnet or testnet fork
    /// @dev checks that the actions do not include the wormhole core address
    /// checks that all action targets are pointing to contracts
    /// @param actions the list of actions for Base or Optimism
    /// @param addresses the addresses contract
    function checkBaseOptimismActions(
        ProposalAction[] memory actions,
        Addresses addresses
    ) public view {
        /// check that we are on the proper chain id here
        require(
            nonMoonbeamChainIds[block.chainid],
            "cannot run base/optimism checks on non-base/optimism network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            baseChainId
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            baseSepoliaChainId
        );

        address wormholeCoreOptimism = addresses.getAddress(
            "WORMHOLE_CORE",
            optimismChainId
        );
        address wormholeCoreOptimismSepolia = addresses.getAddress(
            "WORMHOLE_CORE",
            optimismSepoliaChainId
        );

        for (uint256 i = 0; i < actions.length; i++) {
            require(
                actions[i].data.length > 0 || actions[i].value > 0,
                "action has no value or data"
            );

            address target = actions[i].target;

            /// there's 0 reason for any proposal actions to call addresses with 0 bytecode
            require(
                target.code.length > 0,
                "target for base/optimism action not a contract"
            );

            /// assert wormhole core BASE/Optimism or BASE/Optimism Sepolia
            /// address is not in the list of targets on Base
            require(
                target != wormholeCoreBase,
                "Wormhole Core BASE address should not be in the list of targets"
            );
            require(
                target != wormholeCoreBaseSepolia,
                "Wormhole Core BASE Sepolia address should not be in the list of targets"
            );
            require(
                target != wormholeCoreOptimism,
                "Wormhole Core Optimism address should not be in the list of targets"
            );
            require(
                target != wormholeCoreOptimismSepolia,
                "Wormhole Core Optimism Sepolia address should not be in the list of targets"
            );
        }
    }
    /// @notice should only be run while on Base or Optimism mainnet or testnet fork
    /// @dev checks that the actions do not include the wormhole core address
    /// checks that all action targets are pointing to contracts
    /// @param targets the list of targets for Base or Optimism
    /// @param addresses the addresses contract
    function checkBaseOptimismActions(
        address[] memory targets,
        Addresses addresses
    ) public view {
        /// check that we are on the proper chain id
        require(
            nonMoonbeamChainIds[block.chainid],
            "cannot run base/optimism checks on non-base/optimism network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            baseChainId
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            baseSepoliaChainId
        );

        address wormholeCoreOptimism = addresses.getAddress(
            "WORMHOLE_CORE",
            optimismChainId
        );
        address wormholeCoreOptimismSepolia = addresses.getAddress(
            "WORMHOLE_CORE",
            optimismSepoliaChainId
        );

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            /// there's 0 reason for any proposal actions to call addresses with 0 bytecode
            require(
                target.code.length > 0,
                "target for base/optimism action not a contract"
            );

            /// assert wormhole core BASE/Optimism or BASE/Optimism Sepolia
            /// address is not in the list of targets on Base
            require(
                target != wormholeCoreBase,
                "Wormhole Core BASE address should not be in the list of targets"
            );
            require(
                target != wormholeCoreBaseSepolia,
                "Wormhole Core BASE Sepolia address should not be in the list of targets"
            );
            require(
                target != wormholeCoreOptimism,
                "Wormhole Core Optimism address should not be in the list of targets"
            );
            require(
                target != wormholeCoreOptimismSepolia,
                "Wormhole Core Optimism Sepolia address should not be in the list of targets"
            );
        }
    }

    /// @notice checks actions on both moonbeam and base
    /// ensures neither targets wormhole core on either chain
    /// @param addresses the addresses contract
    /// @param moonbeamActions the list of actions for the moonbeam chain
    function checkMoonbeamActions(
        Addresses addresses,
        ProposalAction[] memory moonbeamActions
    ) public view {
        address wormholeCoreMoonbase = addresses.getAddress(
            "WORMHOLE_CORE_MOONBASE",
            moonBaseChainId
        );
        address wormholeCoreMoonbeam = addresses.getAddress(
            "WORMHOLE_CORE_MOONBEAM",
            moonBeamChainId
        );

        for (uint256 i = 0; i < moonbeamActions.length; i++) {
            /// require all moonbeam actions targets are contracts
            require(
                moonbeamActions[i].target.code.length > 0,
                "target for Moonbeam action not a contract"
            );

            /// require all targets are not wormhole core as this is generated
            /// by the HybridProposal contract
            require(
                moonbeamActions[i].target != wormholeCoreMoonbase,
                "Wormhole Core Moonbase address should not be in the list of targets"
            );
            require(
                moonbeamActions[i].target != wormholeCoreMoonbeam,
                "Wormhole Core Moonbeam address should not be in the list of targets"
            );
        }
    }

    function getTargetsPayloadsValues(
        Addresses addresses
    )
        public
        view
        virtual
        returns (address[] memory, uint256[] memory, bytes[] memory);
}

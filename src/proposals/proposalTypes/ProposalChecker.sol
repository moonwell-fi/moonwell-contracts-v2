//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, MOONBASE_CHAIN_ID, BASE_SEPOLIA_CHAIN_ID, OPTIMISM_CHAIN_ID, OPTIMISM_SEPOLIA_CHAIN_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {AddressToString} from "@protocol/xWELL/axelarInterfaces/AddressString.sol";

abstract contract ProposalChecker {
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
            MOONBEAM_CHAIN_ID == block.chainid ||
                MOONBASE_CHAIN_ID == block.chainid,
            "cannot run Moonbeam checks on non-Moonbeam network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            BASE_CHAIN_ID
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            BASE_SEPOLIA_CHAIN_ID
        );

        address temporalGovBase = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            BASE_CHAIN_ID
        );
        address temporalGovBaseSepolia = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            BASE_SEPOLIA_CHAIN_ID
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

    /// @notice should only be run while on the Base fork
    /// @dev checks that the Base actions do not include the wormhole core address
    /// @param targets the list of targets for the Base actions
    /// @param addresses the addresses contract
    function checkBaseOptimismActions(
        address[] memory targets,
        Addresses addresses
    ) public view {
        require(
            BASE_CHAIN_ID == block.chainid ||
                BASE_SEPOLIA_CHAIN_ID == block.chainid ||
                OPTIMISM_CHAIN_ID == block.chainid ||
                OPTIMISM_SEPOLIA_CHAIN_ID == block.chainid,
            "cannot run base/optimism checks on non-base/optimism network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            BASE_CHAIN_ID
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            BASE_SEPOLIA_CHAIN_ID
        );

        address wormholeCoreOptimism = addresses.getAddress(
            "WORMHOLE_CORE",
            OPTIMISM_CHAIN_ID
        );
        address wormholeCoreOptimismSepolia = addresses.getAddress(
            "WORMHOLE_CORE",
            OPTIMISM_SEPOLIA_CHAIN_ID
        );

        for (uint256 i = 0; i < targets.length; i++) {
            /// there's 0 reason for any proposal actions to call addresses with 0 bytecode
            require(
                targets[i].code.length > 0,
                "target for base action not a contract"
            );

            /// assert wormhole core BASE or BASE Sepolia address is not in the list of targets on Base
            require(
                targets[i] != wormholeCoreBase,
                "Wormhole Core BASE address should not be in the list of targets"
            );
            require(
                targets[i] != wormholeCoreBaseSepolia,
                "Wormhole Core BASE Sepolia address should not be in the list of targets"
            );
            require(
                targets[i] != wormholeCoreOptimism,
                "Wormhole Core Optimism address should not be in the list of targets"
            );
            require(
                targets[i] != wormholeCoreOptimismSepolia,
                "Wormhole Core Optimism Sepolia address should not be in the list of targets"
            );
        }
    }

    /// @notice checks actions on both moonbeam and base
    /// ensures neither targets wormhole core on either chain
    /// @param addresses the addresses contract
    /// @param baseActions the list of actions for the base chain
    /// @param moonbeamActions the list of actions for the moonbeam chain
    function checkMoonbeamBaseActions(
        Addresses addresses,
        ProposalAction[] memory baseActions,
        ProposalAction[] memory moonbeamActions
    ) public view {
        {
            address wormholeCoreBase = addresses.getAddress(
                "WORMHOLE_CORE_BASE",
                BASE_CHAIN_ID
            );
            address wormholeCoreBaseSepolia = addresses.getAddress(
                "WORMHOLE_CORE_SEPOLIA_BASE",
                BASE_SEPOLIA_CHAIN_ID
            );

            address wormholeCoreMoonbase = addresses.getAddress(
                "WORMHOLE_CORE_MOONBASE",
                MOONBASE_CHAIN_ID
            );
            address wormholeCoreMoonbeam = addresses.getAddress(
                "WORMHOLE_CORE_MOONBEAM",
                MOONBEAM_CHAIN_ID
            );

            address wormholeCoreOptimism = addresses.getAddress(
                "WORMHOLE_CORE",
                OPTIMISM_CHAIN_ID
            );
            address wormholeCoreOptimismSepolia = addresses.getAddress(
                "WORMHOLE_CORE",
                OPTIMISM_SEPOLIA_CHAIN_ID
            );

            for (uint256 i = 0; i < moonbeamActions.length; i++) {
                require(
                    moonbeamActions[i].target != wormholeCoreBase,
                    "Wormhole Core Base address should not be in the list of targets"
                );
                require(
                    moonbeamActions[i].target != wormholeCoreBaseSepolia,
                    "Wormhole Core Base Sepolia address should not be in the list of targets"
                );

                require(
                    moonbeamActions[i].target != wormholeCoreOptimism,
                    "Wormhole Core Optimism address should not be in the list of targets"
                );
                require(
                    moonbeamActions[i].target != wormholeCoreOptimismSepolia,
                    "Wormhole Core Optimism Sepolia address should not be in the list of targets"
                );

                require(
                    moonbeamActions[i].target != wormholeCoreMoonbeam,
                    "Wormhole Core Moonbeam address should not be in the list of targets"
                );
                require(
                    moonbeamActions[i].target != wormholeCoreMoonbase,
                    "Wormhole Core Moonbase should not be in the list of targets"
                );
            }

            for (uint256 i = 0; i < baseActions.length; i++) {
                require(
                    baseActions[i].target != wormholeCoreBase,
                    "Wormhole Core Base address should not be in the list of targets"
                );
                require(
                    baseActions[i].target != wormholeCoreBaseSepolia,
                    "Wormhole Core Base Sepolia address should not be in the list of targets"
                );

                require(
                    baseActions[i].target != wormholeCoreMoonbeam,
                    "Wormhole Core Moonbeam address should not be in the list of targets"
                );
                require(
                    baseActions[i].target != wormholeCoreMoonbase,
                    "Wormhole Core Moonbase should not be in the list of targets"
                );
            }
        }

        {
            (address[] memory targets, , ) = getTargetsPayloadsValues(
                addresses
            );

            if (baseActions.length > 0 && moonbeamActions.length > 1) {
                require(
                    targets[targets.length - 1] ==
                        (
                            block.chainid == MOONBEAM_CHAIN_ID ||
                                block.chainid == BASE_CHAIN_ID
                                ? addresses.getAddress(
                                    "WORMHOLE_CORE_MOONBEAM",
                                    MOONBEAM_CHAIN_ID
                                )
                                : addresses.getAddress(
                                    "WORMHOLE_CORE_MOONBASE",
                                    MOONBASE_CHAIN_ID
                                )
                        ),
                    string(
                        abi.encodePacked(
                            "final target should be wormhole core instead got: ",
                            targets[targets.length - 1].toString()
                        )
                    )
                );
            }
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

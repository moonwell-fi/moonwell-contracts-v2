//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";

abstract contract ProposalChecker is ChainIds {
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
                "target for Moonbeam action not a contract"
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
    function checkBaseActions(
        address[] memory targets,
        Addresses addresses
    ) public view {
        require(
            baseChainId == block.chainid || baseSepoliaChainId == block.chainid,
            "cannot run base checks on non-base network"
        );

        address wormholeCoreBase = addresses.getAddress(
            "WORMHOLE_CORE_BASE",
            baseChainId
        );
        address wormholeCoreBaseSepolia = addresses.getAddress(
            "WORMHOLE_CORE_SEPOLIA_BASE",
            baseSepoliaChainId
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
                baseChainId
            );
            address wormholeCoreBaseSepolia = addresses.getAddress(
                "WORMHOLE_CORE_SEPOLIA_BASE",
                baseSepoliaChainId
            );

            address wormholeCoreMoonbase = addresses.getAddress(
                "WORMHOLE_CORE_MOONBASE",
                moonBaseChainId
            );
            address wormholeCoreMoonbeam = addresses.getAddress(
                "WORMHOLE_CORE_MOONBEAM",
                moonBeamChainId
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

            if (baseActions.length > 0) {
                require(
                    targets[targets.length - 1] ==
                        (
                            block.chainid == moonBeamChainId ||
                                block.chainid == baseChainId
                                ? addresses.getAddress(
                                    "WORMHOLE_CORE_MOONBEAM",
                                    moonBeamChainId
                                )
                                : addresses.getAddress(
                                    "WORMHOLE_CORE_MOONBASE",
                                    moonBaseChainId
                                )
                        ),
                    "final target should be wormhole core"
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
        returns (address[] memory, uint256[] memory, bytes[] memory)
    {}
}

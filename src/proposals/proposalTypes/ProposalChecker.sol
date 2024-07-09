//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {
    MOONBASE_CHAIN_ID, MOONBEAM_CHAIN_ID
} from "@protocol/utils/ChainIds.sol";
import {AddressToString} from
    "@protocol/xWELL/axelarInterfaces/AddressString.sol";
import {ChainIds} from "@utils/ChainIds.sol";

abstract contract ProposalChecker {
    using ChainIds for uint256;
    using AddressToString for address;

    /// @notice should only be run while on the Moonbeam fork
    /// @dev checks that the Moonbeam actions do not include the Base wormhole core address and temporal governor address
    /// @param targets the list of targets for the Moonbeam actions
    function checkMoonbeamActions(address[] memory targets) public view {
        require(
            MOONBEAM_CHAIN_ID == block.chainid
                || MOONBASE_CHAIN_ID == block.chainid,
            "cannot run Moonbeam checks on non-Moonbeam network"
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
        }
    }

    /// @notice should only be run while on Base or Optimism mainnet or testnet fork
    /// @dev checks that the actions do not include the wormhole core address
    /// checks that all action targets are pointing to contracts
    /// @param actions the list of actions for Base or Optimism
    function checkBaseOptimismActions(ProposalAction[] memory actions)
        public
        view
    {
        /// check that we are on the proper chain id here
        require(
            block.chainid.nonMoonbeamChainIds(),
            "cannot run base/optimism checks on non-base/optimism network"
        );

        address[] memory targets = new address[](actions.length);
        for (uint256 i = 0; i < actions.length; i++) {
            require(
                actions[i].data.length > 0 || actions[i].value > 0,
                "action has no value or data"
            );
            targets[i] = actions[i].target;
        }

        checkBaseOptimismActions(targets);
    }

    /// @notice should only be run while on Base or Optimism mainnet or testnet fork
    /// @dev checks that the actions all have bytecode
    /// @param targets the list of targets for Base or Optimism
    function checkBaseOptimismActions(address[] memory targets) public view {
        /// check that we are on the proper chain id
        require(
            block.chainid.nonMoonbeamChainIds(),
            "cannot run base/optimism checks on non-base/optimism network"
        );

        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];

            /// there's 0 reason for any proposal actions to call addresses with 0 bytecode
            require(
                target.code.length > 0,
                "target for base/optimism action not a contract"
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
        address wormholeCoreMoonbase =
            addresses.getAddress("WORMHOLE_CORE", MOONBASE_CHAIN_ID);
        address wormholeCoreMoonbeam =
            addresses.getAddress("WORMHOLE_CORE", MOONBEAM_CHAIN_ID);

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

    function getTargetsPayloadsValues(Addresses addresses)
        public
        view
        virtual
        returns (address[] memory, uint256[] memory, bytes[] memory);
}

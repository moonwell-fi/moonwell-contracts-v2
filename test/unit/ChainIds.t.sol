// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds, BASE_CHAIN_ID, BASE_SEPOLIA_CHAIN_ID, ETHEREUM_CHAIN_ID, ETHEREUM_SEPOLIA_CHAIN_ID, MOONBASE_CHAIN_ID, MOONBEAM_CHAIN_ID, OPTIMISM_CHAIN_ID, OPTIMISM_SEPOLIA_CHAIN_ID} from "@protocol/utils/ChainIds.sol";

contract ChainIdsUnitTest is Test {
    using ChainIds for uint256;

    /// @notice Every toXChainId converter must accept its own chain id as input
    /// and return it unchanged. Regression for the former toEthereumChainId
    /// inconsistency where Ethereum/Sepolia inputs reverted.
    function testEachConverterAcceptsOwnMainnetChainId() public pure {
        assertEq(
            ChainIds.toEthereumChainId(ETHEREUM_CHAIN_ID),
            ETHEREUM_CHAIN_ID,
            "ethereum converter must accept ethereum mainnet"
        );
        assertEq(
            ChainIds.toBaseChainId(BASE_CHAIN_ID),
            BASE_CHAIN_ID,
            "base converter must accept base mainnet"
        );
        assertEq(
            ChainIds.toOptimismChainId(OPTIMISM_CHAIN_ID),
            OPTIMISM_CHAIN_ID,
            "optimism converter must accept optimism mainnet"
        );
        assertEq(
            ChainIds.toMoonbeamChainId(MOONBEAM_CHAIN_ID),
            MOONBEAM_CHAIN_ID,
            "moonbeam converter must accept moonbeam mainnet"
        );
    }

    /// @notice Every toXChainId converter must accept its own testnet chain id
    /// and return the matching testnet id.
    function testEachConverterAcceptsOwnTestnetChainId() public pure {
        assertEq(
            ChainIds.toEthereumChainId(ETHEREUM_SEPOLIA_CHAIN_ID),
            ETHEREUM_SEPOLIA_CHAIN_ID,
            "ethereum converter must accept sepolia"
        );
        assertEq(
            ChainIds.toBaseChainId(BASE_SEPOLIA_CHAIN_ID),
            BASE_SEPOLIA_CHAIN_ID,
            "base converter must accept base sepolia"
        );
        assertEq(
            ChainIds.toOptimismChainId(OPTIMISM_SEPOLIA_CHAIN_ID),
            OPTIMISM_SEPOLIA_CHAIN_ID,
            "optimism converter must accept optimism sepolia"
        );
        assertEq(
            ChainIds.toMoonbeamChainId(MOONBASE_CHAIN_ID),
            MOONBASE_CHAIN_ID,
            "moonbeam converter must accept moonbase"
        );
    }

    function testToEthereumChainIdMapsAllMainnetSiblings() public pure {
        assertEq(ChainIds.toEthereumChainId(BASE_CHAIN_ID), ETHEREUM_CHAIN_ID);
        assertEq(
            ChainIds.toEthereumChainId(OPTIMISM_CHAIN_ID),
            ETHEREUM_CHAIN_ID
        );
        assertEq(
            ChainIds.toEthereumChainId(MOONBEAM_CHAIN_ID),
            ETHEREUM_CHAIN_ID
        );
    }

    function testToEthereumChainIdMapsAllTestnetSiblings() public pure {
        assertEq(
            ChainIds.toEthereumChainId(BASE_SEPOLIA_CHAIN_ID),
            ETHEREUM_SEPOLIA_CHAIN_ID
        );
        assertEq(
            ChainIds.toEthereumChainId(OPTIMISM_SEPOLIA_CHAIN_ID),
            ETHEREUM_SEPOLIA_CHAIN_ID
        );
        assertEq(
            ChainIds.toEthereumChainId(MOONBASE_CHAIN_ID),
            ETHEREUM_SEPOLIA_CHAIN_ID
        );
    }

    function testToEthereumChainIdRevertsOnUnknownChain() public {
        vm.expectRevert("ChainIds: invalid chain id to ethereum chain id");
        this.externalToEthereumChainId(999999);
    }

    /// @dev external wrapper so vm.expectRevert sees the revert one frame down,
    /// library internal functions inline into the caller otherwise.
    function externalToEthereumChainId(
        uint256 chainId
    ) external pure returns (uint256) {
        return ChainIds.toEthereumChainId(chainId);
    }
}

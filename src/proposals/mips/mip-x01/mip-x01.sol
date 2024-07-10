//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Address} from "@utils/Address.sol";
import {Configs} from "@proposals/Configs.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipx01 is HybridProposal, Configs {
    using ChainIds for uint256;

    string public constant override name =
        "MIP-X01: xWELL and Multichain Governor Upgrade";

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    /// Moonbeam logic contract deployment
    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("NEW_MULTICHAIN_GOVERNOR_IMPL")) {
            MultichainGovernor newImpl = new MultichainGovernor();
            addresses.addAddress(
                "NEW_MULTICHAIN_GOVERNOR_IMPL",
                address(newImpl)
            );
        }

        if (!addresses.isAddressSet("NEW_XWELL_IMPL")) {
            xWELL newImpl = new xWELL();
            addresses.addAddress("NEW_XWELL_IMPL", address(newImpl));
        }
    }

    function build(Addresses addresses) public override {
        vm.selectFork(primaryForkId());

        /// upgrade the multichain governor on Moonbeam
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                addresses.getAddress("NEW_MULTICHAIN_GOVERNOR_IMPL")
            ),
            "Upgrade the Multichain Governor implementation on Moonbeam",
            ActionType.Moonbeam
        );

        /// update xWELL implementation across both Moonbeam and Base
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("NEW_XWELL_IMPL")
            ),
            "Upgrade the xWELL implementation on Moonbeam",
            ActionType.Moonbeam
        );

        uint256 baseChainId = block.chainid.toBaseChainId();
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN", baseChainId),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY", baseChainId),
                addresses.getAddress("NEW_XWELL_IMPL", baseChainId)
            ),
            "Upgrade the xWELL implementation on Base",
            ActionType.Base
        );

        /// upgrade the multichain vote collection on Base
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN", baseChainId),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("VOTE_COLLECTION_PROXY", baseChainId),
                addresses.getAddress("NEW_VOTE_COLLECTION_IMPL", baseChainId)
            ),
            "Upgrade the Multichain Vote Collection implementation on Base",
            ActionType.Base
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        /// check that the xWELL implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("NEW_XWELL_IMPL"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam xWELL_PROXY validation"
        );
        /// check that the Multichain Governor implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            addresses.getAddress("NEW_MULTICHAIN_GOVERNOR_IMPL"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam MULTICHAIN_GOVERNOR_IMPL validation"
        );

        vm.selectFork(BASE_FORK_ID);
        /// check that the xWELL implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("NEW_XWELL_IMPL"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "Base xWELL_PROXY validation"
        );
        /// check that the Multichain Vote Collection implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("VOTE_COLLECTION_PROXY"),
            addresses.getAddress("NEW_VOTE_COLLECTION_IMPL"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "Base VOTE_COLLECTION_PROXY validation"
        );

        vm.selectFork(primaryForkId());
    }
}

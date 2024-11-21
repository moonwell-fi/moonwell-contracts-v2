//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {IMetaMorpho} from "@protocol/morpho/IMetaMorpho.sol";

contract mipb36 is HybridProposal, Configs {
    string public constant override name = "MIP-B36";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b36/MIP-B36.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                addresses.getAddress("MORPHO_PUBLIC_ALLOCATOR"),
                true
            ),
            "Set allocator for EURC Vault to Morpho Public Allocator"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        IMetaMorpho vault = IMetaMorpho(
            addresses.getAddress("EURC_METAMORPHO_VAULT")
        );

        assertEq(
            vault.isAllocator(addresses.getAddress("MORPHO_PUBLIC_ALLOCATOR")),
            true
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IMetaMorphoBase} from "@protocol/morpho/IMetaMorpho.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @title MIP-B56: Transfer Risk Curatorship for Moonwell Vaults (Base) to Anthias Labs
/// @notice Transfers the risk curator role for Moonwell's Morpho vaults on Base
///         from BlockAnalitica / B.Protocol to Anthias Labs, updates fee recipients,
///         and adds Anthias as allocator.
/// @dev This proposal:
///      1. Calls setCurator on flagship vaults to transfer curator role
///      2. Calls setFeeRecipient on all vaults to point to new FeeSplitter contracts
///      3. Calls setIsAllocator to add Anthias EOA as allocator for all vaults
contract mipb56 is HybridProposal, Configs {
    string public constant override name = "MIP-B56";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b56/b56.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        address anthiasCurator = addresses.getAddress("ANTHIAS_MULTISIG");
        address anthiasAllocator = addresses.getAddress("ANTHIAS_EOA");

        // ============ Transfer Curator Role (Flagship Vaults Only) ============
        // Note: meUSDC already has Anthias as curator from MIP-B47

        // Transfer curator role for USDC MetaMorpho Vault to Anthias Labs
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setCurator(address)", anthiasCurator),
            "Transfer USDC vault curator to Anthias Labs"
        );

        // Transfer curator role for WETH MetaMorpho Vault to Anthias Labs
        _pushAction(
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setCurator(address)", anthiasCurator),
            "Transfer WETH vault curator to Anthias Labs"
        );

        // Transfer curator role for EURC MetaMorpho Vault to Anthias Labs
        _pushAction(
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setCurator(address)", anthiasCurator),
            "Transfer EURC vault curator to Anthias Labs"
        );

        // Transfer curator role for cbBTC MetaMorpho Vault to Anthias Labs
        _pushAction(
            addresses.getAddress("cbBTC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setCurator(address)", anthiasCurator),
            "Transfer cbBTC vault curator to Anthias Labs"
        );

        // ============ Update Fee Recipients ============

        // Set new fee recipient for USDC vault
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setFeeRecipient(address)",
                addresses.getAddress("USDC_METAMORPHO_FEE_SPLITTER_V2")
            ),
            "Set USDC vault fee recipient to new FeeSplitter"
        );

        // Set new fee recipient for WETH vault
        _pushAction(
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setFeeRecipient(address)",
                addresses.getAddress("WETH_METAMORPHO_FEE_SPLITTER_V2")
            ),
            "Set WETH vault fee recipient to new FeeSplitter"
        );

        // Set new fee recipient for EURC vault
        _pushAction(
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setFeeRecipient(address)",
                addresses.getAddress("EURC_METAMORPHO_FEE_SPLITTER_V2")
            ),
            "Set EURC vault fee recipient to new FeeSplitter"
        );

        // Set new fee recipient for cbBTC vault
        _pushAction(
            addresses.getAddress("cbBTC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setFeeRecipient(address)",
                addresses.getAddress("cbBTC_METAMORPHO_FEE_SPLITTER")
            ),
            "Set cbBTC vault fee recipient to new FeeSplitter"
        );

        // Set new fee recipient for meUSDC vault
        _pushAction(
            addresses.getAddress("meUSDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setFeeRecipient(address)",
                addresses.getAddress("meUSDC_METAMORPHO_FEE_SPLITTER")
            ),
            "Set meUSDC vault fee recipient to new FeeSplitter"
        );

        // ============ Add Anthias as Allocator ============

        // Add Anthias EOA as allocator for USDC vault
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                anthiasAllocator,
                true
            ),
            "Add Anthias as allocator for USDC vault"
        );

        // Add Anthias EOA as allocator for WETH vault
        _pushAction(
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                anthiasAllocator,
                true
            ),
            "Add Anthias as allocator for WETH vault"
        );

        // Add Anthias EOA as allocator for EURC vault
        _pushAction(
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                anthiasAllocator,
                true
            ),
            "Add Anthias as allocator for EURC vault"
        );

        // Add Anthias EOA as allocator for cbBTC vault
        _pushAction(
            addresses.getAddress("cbBTC_METAMORPHO_VAULT"),
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                anthiasAllocator,
                true
            ),
            "Add Anthias as allocator for cbBTC vault"
        );

        // Note: meUSDC already has Anthias EOA as allocator (set in MIP-B49)
    }

    function teardown(Addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        address anthiasCurator = addresses.getAddress("ANTHIAS_MULTISIG");
        address anthiasAllocator = addresses.getAddress("ANTHIAS_EOA");

        // ============ Validate Curator ============

        // Validate USDC vault curator
        assertEq(
            IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                .curator(),
            anthiasCurator,
            "USDC vault curator should be Anthias Labs"
        );

        // Validate WETH vault curator
        assertEq(
            IMetaMorphoBase(addresses.getAddress("WETH_METAMORPHO_VAULT"))
                .curator(),
            anthiasCurator,
            "WETH vault curator should be Anthias Labs"
        );

        // Validate EURC vault curator
        assertEq(
            IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                .curator(),
            anthiasCurator,
            "EURC vault curator should be Anthias Labs"
        );

        // Validate cbBTC vault curator
        assertEq(
            IMetaMorphoBase(addresses.getAddress("cbBTC_METAMORPHO_VAULT"))
                .curator(),
            anthiasCurator,
            "cbBTC vault curator should be Anthias Labs"
        );

        // Validate meUSDC vault curator (already set by MIP-B47)
        assertEq(
            IMetaMorphoBase(addresses.getAddress("meUSDC_METAMORPHO_VAULT"))
                .curator(),
            anthiasCurator,
            "meUSDC vault curator should be Anthias Labs"
        );

        // ============ Validate Fee Recipients ============

        // Validate USDC vault fee recipient
        assertEq(
            IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                .feeRecipient(),
            addresses.getAddress("USDC_METAMORPHO_FEE_SPLITTER_V2"),
            "USDC vault fee recipient should be new FeeSplitter"
        );

        // Validate WETH vault fee recipient
        assertEq(
            IMetaMorphoBase(addresses.getAddress("WETH_METAMORPHO_VAULT"))
                .feeRecipient(),
            addresses.getAddress("WETH_METAMORPHO_FEE_SPLITTER_V2"),
            "WETH vault fee recipient should be new FeeSplitter"
        );

        // Validate EURC vault fee recipient
        assertEq(
            IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                .feeRecipient(),
            addresses.getAddress("EURC_METAMORPHO_FEE_SPLITTER_V2"),
            "EURC vault fee recipient should be new FeeSplitter"
        );

        // Validate cbBTC vault fee recipient
        assertEq(
            IMetaMorphoBase(addresses.getAddress("cbBTC_METAMORPHO_VAULT"))
                .feeRecipient(),
            addresses.getAddress("cbBTC_METAMORPHO_FEE_SPLITTER"),
            "cbBTC vault fee recipient should be new FeeSplitter"
        );

        // Validate meUSDC vault fee recipient
        assertEq(
            IMetaMorphoBase(addresses.getAddress("meUSDC_METAMORPHO_VAULT"))
                .feeRecipient(),
            addresses.getAddress("meUSDC_METAMORPHO_FEE_SPLITTER"),
            "meUSDC vault fee recipient should be new FeeSplitter"
        );

        // ============ Validate Allocator ============

        // Validate USDC vault allocator
        assertTrue(
            IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                .isAllocator(anthiasAllocator),
            "Anthias should be allocator for USDC vault"
        );

        // Validate WETH vault allocator
        assertTrue(
            IMetaMorphoBase(addresses.getAddress("WETH_METAMORPHO_VAULT"))
                .isAllocator(anthiasAllocator),
            "Anthias should be allocator for WETH vault"
        );

        // Validate EURC vault allocator
        assertTrue(
            IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                .isAllocator(anthiasAllocator),
            "Anthias should be allocator for EURC vault"
        );

        // Validate cbBTC vault allocator
        assertTrue(
            IMetaMorphoBase(addresses.getAddress("cbBTC_METAMORPHO_VAULT"))
                .isAllocator(anthiasAllocator),
            "Anthias should be allocator for cbBTC vault"
        );

        // Validate meUSDC vault allocator
        assertTrue(
            IMetaMorphoBase(addresses.getAddress("meUSDC_METAMORPHO_VAULT"))
                .isAllocator(anthiasAllocator),
            "Anthias should be allocator for meUSDC vault"
        );
    }
}

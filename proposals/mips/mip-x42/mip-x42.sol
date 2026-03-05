//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {MarketUpdateTemplate} from "@proposals/templates/MarketUpdate.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice MIP-X42: Anthias Labs Monthly Recommendations + Warden Allocator Removal
/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// proposals/mips/mip-x42/mip-x42.sol:mipx42
contract mipx42 is MarketUpdateTemplate {
    /// @notice Old allocator address (BlockAnalitica) to be removed
    address public constant OLD_ALLOCATOR =
        0x76E21F76cdD96AE6678a4383d2cc6cF61f925564;

    function name() external pure override returns (string memory) {
        return "MIP-X42";
    }

    function build(Addresses addresses) public override {
        /// First, call parent to build market update actions
        super.build(addresses);

        /// Then add allocator removal actions on Base
        vm.selectFork(BASE_FORK_ID);

        address publicAllocator = addresses.getAddress(
            "MORPHO_PUBLIC_ALLOCATOR"
        );

        /// Vault addresses
        address usdcVault = addresses.getAddress("USDC_METAMORPHO_VAULT");
        address wethVault = addresses.getAddress("WETH_METAMORPHO_VAULT");
        address eurcVault = addresses.getAddress("EURC_METAMORPHO_VAULT");
        address cbbtcVault = addresses.getAddress("cbBTC_METAMORPHO_VAULT");

        /// ============================================
        /// 1. Disable OLD_ALLOCATOR as allocator on all vaults
        /// ============================================

        _pushAction(
            usdcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                OLD_ALLOCATOR,
                false
            ),
            "Disable Warden as allocator on USDC vault"
        );

        _pushAction(
            wethVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                OLD_ALLOCATOR,
                false
            ),
            "Disable Warden as allocator on WETH vault"
        );

        _pushAction(
            eurcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                OLD_ALLOCATOR,
                false
            ),
            "Disable Warden as allocator on EURC vault"
        );

        _pushAction(
            cbbtcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                OLD_ALLOCATOR,
                false
            ),
            "Disable Warden as allocator on cbBTC vault"
        );

        /// ============================================
        /// 2. Disable Public Allocator as allocator on all vaults
        /// ============================================

        _pushAction(
            usdcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                publicAllocator,
                false
            ),
            "Disable Public Allocator on USDC vault"
        );

        _pushAction(
            wethVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                publicAllocator,
                false
            ),
            "Disable Public Allocator on WETH vault"
        );

        _pushAction(
            eurcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                publicAllocator,
                false
            ),
            "Disable Public Allocator on EURC vault"
        );

        _pushAction(
            cbbtcVault,
            abi.encodeWithSignature(
                "setIsAllocator(address,bool)",
                publicAllocator,
                false
            ),
            "Disable Public Allocator on cbBTC vault"
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        /// First, validate parent market updates
        super.validate(addresses, deployer);

        /// Then validate allocator changes on Base
        vm.selectFork(BASE_FORK_ID);

        address publicAllocator = addresses.getAddress(
            "MORPHO_PUBLIC_ALLOCATOR"
        );

        address usdcVault = addresses.getAddress("USDC_METAMORPHO_VAULT");
        address wethVault = addresses.getAddress("WETH_METAMORPHO_VAULT");
        address eurcVault = addresses.getAddress("EURC_METAMORPHO_VAULT");
        address cbbtcVault = addresses.getAddress("cbBTC_METAMORPHO_VAULT");

        /// Validate OLD_ALLOCATOR is no longer allocator on any vault
        assertFalse(
            _isAllocator(usdcVault, OLD_ALLOCATOR),
            "BlockAnalitica should not be allocator on USDC vault"
        );
        assertFalse(
            _isAllocator(wethVault, OLD_ALLOCATOR),
            "BlockAnalitica should not be allocator on WETH vault"
        );
        assertFalse(
            _isAllocator(eurcVault, OLD_ALLOCATOR),
            "BlockAnalitica should not be allocator on EURC vault"
        );
        assertFalse(
            _isAllocator(cbbtcVault, OLD_ALLOCATOR),
            "BlockAnalitica should not be allocator on cbBTC vault"
        );

        /// Validate Public Allocator is no longer allocator on any vault
        assertFalse(
            _isAllocator(usdcVault, publicAllocator),
            "Public Allocator should not be allocator on USDC vault"
        );
        assertFalse(
            _isAllocator(wethVault, publicAllocator),
            "Public Allocator should not be allocator on WETH vault"
        );
        assertFalse(
            _isAllocator(eurcVault, publicAllocator),
            "Public Allocator should not be allocator on EURC vault"
        );
        assertFalse(
            _isAllocator(cbbtcVault, publicAllocator),
            "Public Allocator should not be allocator on cbBTC vault"
        );
    }

    function _isAllocator(
        address vault,
        address allocator
    ) internal view returns (bool) {
        (bool success, bytes memory data) = vault.staticcall(
            abi.encodeWithSignature("isAllocator(address)", allocator)
        );
        require(success, "isAllocator call failed");
        return abi.decode(data, (bool));
    }
}

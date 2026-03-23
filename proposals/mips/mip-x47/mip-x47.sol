//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import "@forge-std/Test.sol";

import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {RewardsDistributionTemplate} from "@proposals/templates/RewardsDistribution.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// proposals/mips/mip-x47/mip-x47.sol:mipx47
contract mipx47 is RewardsDistributionTemplate {
    string constant WETH_FLAGSHIP = "WETH_FLAGSHIP_METAMORPHO_VAULT";
    string constant USDC_FLAGSHIP = "USDC_FLAGSHIP_METAMORPHO_VAULT";
    string constant EURC_FLAGSHIP = "EURC_FLAGSHIP_METAMORPHO_VAULT";
    string constant cbBTC_FRONTIER = "cbBTC_FRONTIER_METAMORPHO_VAULT";

    function build(Addresses addresses) public override {
        /// standard rewards distribution actions
        super.build(addresses);

        /// select Base fork for vault ownership actions
        vm.selectFork(BASE_FORK_ID);

        /// accept ownership of Flagship/Frontier MetaMorpho vaults
        _pushAction(
            addresses.getAddress(WETH_FLAGSHIP),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the WETH Flagship MetaMorpho Vault"
        );

        _pushAction(
            addresses.getAddress(USDC_FLAGSHIP),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the USDC Flagship MetaMorpho Vault"
        );

        _pushAction(
            addresses.getAddress(EURC_FLAGSHIP),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the EURC Flagship MetaMorpho Vault"
        );

        _pushAction(
            addresses.getAddress(cbBTC_FRONTIER),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the cbBTC Frontier MetaMorpho Vault"
        );
    }

    function validate(Addresses addresses, address a) public override {
        /// standard rewards distribution validation
        super.validate(addresses, a);

        /// select Base fork for vault ownership validation
        vm.selectFork(BASE_FORK_ID);

        /// validate vault ownership transferred to TEMPORAL_GOVERNOR
        _validateVaultOwnership(addresses, WETH_FLAGSHIP, "WETH Flagship");
        _validateVaultOwnership(addresses, USDC_FLAGSHIP, "USDC Flagship");
        _validateVaultOwnership(addresses, EURC_FLAGSHIP, "EURC Flagship");
        _validateVaultOwnership(addresses, cbBTC_FRONTIER, "cbBTC Frontier");
    }

    function _validateVaultOwnership(
        Addresses addresses,
        string memory vaultName,
        string memory label
    ) internal view {
        address vaultAddress = addresses.getAddress(vaultName);

        assertEq(
            Ownable2StepUpgradeable(vaultAddress).owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            string.concat(label, " vault ownership incorrect")
        );

        assertEq(
            Ownable2StepUpgradeable(vaultAddress).pendingOwner(),
            address(0),
            string.concat(label, " vault pending owner should be cleared")
        );
    }
}

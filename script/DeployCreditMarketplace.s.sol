// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";

/// Deploys the Credit Marketplace per spec §14. All chain-specific
/// addresses are sourced from `chains/<chainId>.json` via the
/// `AllChainAddresses` helper — there are no hardcoded constants here per
/// `.claude/rules/proposals.md`. After this script runs, a governance
/// proposal still needs to whitelist mTokens, principal tokens,
/// collateral tokens, and set default params (see §14.3 post-deploy
/// checklist).
///
/// Env vars required:
///   BACKEND_SIGNER  — EOA address holding the backend's cold signing key
///   FEE_RECIPIENT   — address that receives marketplace fees
///
/// Usage:
///   forge script script/DeployCreditMarketplace.s.sol \
///     --rpc-url base --broadcast --verify
contract DeployCreditMarketplace is Script {
    function run()
        external
        returns (CreditLoan loanImpl, CreditMarketplaceFactory factory)
    {
        Addresses addresses = new Addresses();

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address comptroller = addresses.getAddress("UNITROLLER");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address backendSigner = vm.envAddress("BACKEND_SIGNER");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");

        vm.startBroadcast();

        loanImpl = new CreditLoan();
        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            comptroller,
            address(loanImpl),
            backendSigner,
            feeRecipient,
            pauseGuardian
        );

        vm.stopBroadcast();

        console.log("CreditLoan implementation:", address(loanImpl));
        console.log("CreditMarketplaceFactory:", address(factory));
        console.log("Owner (temporal governor):", temporalGovernor);
        console.log("Comptroller (unitroller proxy):", comptroller);
        console.log("Pause guardian:", pauseGuardian);
        console.log("Backend signer:", backendSigner);
        console.log("Fee recipient:", feeRecipient);
    }
}

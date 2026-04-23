// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";

/// Deploys the Credit Marketplace per spec §14. Chain-specific addresses
/// (Temporal Governor, Unitroller, Pause Guardian) come from
/// `chains/<chainId>.json` via `AllChainAddresses` per
/// `.claude/rules/proposals.md`. The backend signer and fee recipient
/// are feature-specific — not yet canonicalized in `chains/*.json` — so
/// they live as constants at the top of this script. Ops must replace
/// them before each mainnet deploy.
///
/// After this script runs, a governance proposal still needs to
/// whitelist mTokens, principal tokens, collateral tokens, and set
/// default params (see §14.3 post-deploy checklist).
///
/// Usage:
///   forge script script/DeployCreditMarketplace.s.sol \
///     --rpc-url base --broadcast --verify
contract DeployCreditMarketplace is Script {
    /// PLACEHOLDER — cold-key EOA that signs BackendTerms for the
    /// matching flow. Replace with the Moonwell ops backend signer
    /// before any mainnet deploy. The factory constructor rejects
    /// `address(0)`, so leaving this unset fails loud at deploy.
    address internal constant BACKEND_SIGNER =
        address(0xBEEf000000000000000000000000000000000001);

    /// PLACEHOLDER — treasury / multisig that receives the marketplace
    /// fee cut. Replace with the Moonwell treasury address before
    /// any mainnet deploy.
    address internal constant FEE_RECIPIENT =
        address(0xfEE0000000000000000000000000000000000002);

    function run()
        external
        returns (CreditLoan loanImpl, CreditMarketplaceFactory factory)
    {
        Addresses addresses = new Addresses();

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address comptroller = addresses.getAddress("UNITROLLER");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");

        vm.startBroadcast();

        loanImpl = new CreditLoan();
        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            comptroller,
            address(loanImpl),
            BACKEND_SIGNER,
            FEE_RECIPIENT,
            pauseGuardian
        );

        vm.stopBroadcast();

        console.log("CreditLoan implementation:", address(loanImpl));
        console.log("CreditMarketplaceFactory:", address(factory));
        console.log("Owner (temporal governor):", temporalGovernor);
        console.log("Comptroller (unitroller proxy):", comptroller);
        console.log("Pause guardian:", pauseGuardian);
        console.log("Backend signer:", BACKEND_SIGNER);
        console.log("Fee recipient:", FEE_RECIPIENT);
    }
}

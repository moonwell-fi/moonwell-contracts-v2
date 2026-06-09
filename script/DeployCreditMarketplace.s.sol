// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {CreditTierRegistry} from "@protocol/marketplace/CreditTierRegistry.sol";
import {DataStreamsAggregatorAdapter, IVerifierProxy} from "@protocol/oracles/DataStreamsAggregatorAdapter.sol";
import {MockDataStreamsVerifierV10} from "@test/mock/MockDataStreamsVerifierV10.sol";

/// Deploys (and optionally configures) the Credit Marketplace per spec §14.
///
/// TWO MODES, selected by the `CONFIGURE` env var:
///
/// 1. PROD (CONFIGURE=false, default) — deploys the 3 contracts only. The
///    factory owner is the Temporal Governor; the registry owner, backend
///    signer, fee recipient, and credit-bureau attestor are read from the chain
///    registry (`chains/<id>.json` via AllChainAddresses). `getAddress` REVERTS
///    if any name isn't registered, so a real deploy can't proceed with an
///    unset address. Whitelisting + params are a later governance MIP
///    (§14.3 checklist).
///
/// 2. FORK (CONFIGURE=true) — deploys with the DEPLOYER as factory + registry
///    owner, then configures everything in the same broadcast (USDC market +
///    cbBTC collateral, staleness, the lender-guard knobs, default params, and
///    the credit-bureau attestor). Feature addresses use the fail-safe
///    placeholders below (no known key — the fork verifies deploy + config
///    wiring, not the off-chain signing flow). Optionally transfers the factory
///    to the real Temporal Governor at the end (`TRANSFER_TO_TG=true`).
///
/// The deployer is supplied by the CLI (`--account <keystore>` + `--sender
/// <addr>`, or `--ledger`, etc.) — this script reads no private key. In FORK
/// mode the deployer becomes the factory + registry owner, so `--sender` must
/// be the address that will run the config.
///
/// Env:
///   CONFIGURE        bool, default false. true = FORK mode.
///   TRANSFER_TO_TG   bool, default false. FORK-only: transfer factory
///                    ownership to the real TG after configuring.
///
/// PROD registry names — must be set in chains/<id>.json before deploy (else
/// getAddress reverts):
///   CREDIT_TIER_REGISTRY_OWNER, CREDIT_MARKETPLACE_BACKEND_SIGNER,
///   CREDIT_MARKETPLACE_FEE_RECIPIENT, CREDIT_BUREAU_ATTESTOR
///
/// Usage:
///   forge script script/DeployCreditMarketplace.s.sol \
///     --rpc-url <fork> --account <keystore> --sender <addr> --broadcast
///   (dry-run: drop --broadcast; simulates the full deploy+config against the fork)
contract DeployCreditMarketplace is Script {
    // Fail-safe FORK-mode placeholders (no known private key). PROD reads the
    // real addresses from the chain registry instead (see _resolveConfig).
    // Backend signer and attestor are kept distinct to mirror the production
    // two-key separation.
    address internal constant PLACEHOLDER_BACKEND_SIGNER =
        0xa000881b0741B75B4800593fF217f9Db7b853903;
    address internal constant PLACEHOLDER_FEE_RECIPIENT =
        0xfEE0000000000000000000000000000000000002;
    address internal constant PLACEHOLDER_ATTESTOR =
        0xA77E570000000000000000000000000000000004;

    // ── "guards ON" config preset (FORK mode), spec §14.3 + risk-report §5.1 ──
    uint32 internal constant STALENESS_WINDOW = 1 days;
    uint32 internal constant FEED_STALENESS = 1 days; // per-feed, <= window
    uint16 internal constant LTV_BUFFER_BPS = 1_000; // 10% global floor
    uint16 internal constant CBBTC_BUFFER_BPS = 3_000; // 30% per-collateral (guard #2)
    uint16 internal constant MOONWELL_HEALTH_BUFFER_BPS = 2_000; // 20% (guard #3)
    uint32 internal constant GRACE_PERIOD = 1 days;
    uint16 internal constant OVER_SEIZURE_BPS = 2_000; // 20%
    uint16 internal constant CONSECUTIVE_MISSES = 2;
    uint16 internal constant MARKETPLACE_FEE_BPS = 500; // 5%

    // wbCOIN collateral via Chainlink Data Streams v10 (tokenized-asset).
    // cbETH is added as an mToken *market* (no per-collateral buffer).
    uint16 internal constant WBCOIN_BUFFER_BPS = 4_000; // 40% (tokenized-equity vol + market-hours gaps)
    uint8 internal constant WBCOIN_PRICE_DECIMALS = 18; // DEMO assumption; confirm vs the real stream
    int192 internal constant WBCOIN_DEMO_PRICE = 250e18; // static fork price (mock); ~$250/share @ 18-dec
    int192 internal constant WBCOIN_MULTIPLIER = 1e18; // 1.0 share per token (1e18 ratio)
    bytes32 internal constant WBCOIN_DS_FEED_ID =
        0x000a9811a9bef734e52059c184312bd9ebf24b3ce5f86285f693eacbb7151baa;

    /// Resolved deploy inputs. A struct keeps `run`'s live-local count below
    /// the optimizer_runs = 1 stack-too-deep threshold.
    struct DeployConfig {
        address factoryOwner;
        address registryOwner;
        address comptroller;
        address pauseGuardian;
        address backendSigner;
        address feeRecipient;
        address attestor;
        address realTg;
        bool configure;
        bool transferToTg;
    }

    function run()
        external
        returns (
            CreditLoan loanImpl,
            CreditMarketplaceFactory factory,
            CreditTierRegistry tierRegistry
        )
    {
        Addresses addresses = new Addresses();
        // Deployer = the CLI-supplied sender (--account/--sender, --ledger, …);
        // no private key is read from env.
        DeployConfig memory cfg = _resolveConfig(addresses, msg.sender);

        vm.startBroadcast();

        loanImpl = new CreditLoan();
        tierRegistry = new CreditTierRegistry(cfg.registryOwner);
        factory = new CreditMarketplaceFactory(
            cfg.factoryOwner,
            cfg.comptroller,
            address(loanImpl),
            cfg.backendSigner,
            cfg.feeRecipient,
            cfg.pauseGuardian,
            address(tierRegistry)
        );

        if (cfg.configure) {
            // factoryOwner == deployer in FORK mode (see _resolveConfig).
            _configure(
                factory,
                tierRegistry,
                addresses,
                cfg.attestor,
                cfg.factoryOwner
            );
            if (cfg.transferToTg) {
                factory.transferOwnership(cfg.realTg);
            }
        }

        vm.stopBroadcast();

        _logSummary(loanImpl, factory, tierRegistry, cfg);
    }

    /// Resolves the mode flags, chain singletons, and feature addresses into a
    /// single config struct.
    ///
    /// FORK (`CONFIGURE=true`): the deployer owns both contracts so it can
    /// configure them in the same broadcast; feature addresses are the
    /// fail-safe placeholders.
    ///
    /// PROD: the factory is owned by the Temporal Governor and every feature
    /// address is read from the chain registry. `getAddress` reverts if a name
    /// isn't set in `chains/<id>.json`, so a real deploy can't proceed with an
    /// unset signer / recipient / owner / attestor.
    function _resolveConfig(
        Addresses addresses,
        address deployer
    ) internal view returns (DeployConfig memory cfg) {
        cfg.configure = vm.envOr("CONFIGURE", false);
        cfg.transferToTg = vm.envOr("TRANSFER_TO_TG", false);
        cfg.realTg = addresses.getAddress("TEMPORAL_GOVERNOR");
        cfg.comptroller = addresses.getAddress("UNITROLLER");
        cfg.pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");

        if (cfg.configure) {
            // FORK/demo: deployer owns + keeps everything. The trusted signers
            // must match the off-chain API/CLI keys, so allow overriding them
            // at broadcast time (DEMO_* env); fall back to fail-safe
            // placeholders when unset.
            cfg.factoryOwner = deployer;
            cfg.registryOwner = deployer;
            cfg.backendSigner = vm.envOr(
                "DEMO_BACKEND_SIGNER",
                PLACEHOLDER_BACKEND_SIGNER
            );
            cfg.feeRecipient = vm.envOr(
                "DEMO_FEE_RECIPIENT",
                PLACEHOLDER_FEE_RECIPIENT
            );
            cfg.attestor = vm.envOr("DEMO_ATTESTOR", PLACEHOLDER_ATTESTOR);
        } else {
            cfg.factoryOwner = cfg.realTg;
            cfg.registryOwner = addresses.getAddress(
                "CREDIT_TIER_REGISTRY_OWNER"
            );
            cfg.backendSigner = addresses.getAddress(
                "CREDIT_MARKETPLACE_BACKEND_SIGNER"
            );
            cfg.feeRecipient = addresses.getAddress(
                "CREDIT_MARKETPLACE_FEE_RECIPIENT"
            );
            cfg.attestor = addresses.getAddress("CREDIT_BUREAU_ATTESTOR");
        }
    }

    function _logSummary(
        CreditLoan loanImpl,
        CreditMarketplaceFactory factory,
        CreditTierRegistry tierRegistry,
        DeployConfig memory cfg
    ) internal view {
        console.log("CreditLoan implementation:", address(loanImpl));
        console.log("CreditTierRegistry:", address(tierRegistry));
        console.log("CreditMarketplaceFactory:", address(factory));
        console.log("Factory owner:", factory.owner());
        console.log("Registry owner:", tierRegistry.owner());
        console.log("Backend signer:", cfg.backendSigner);
        console.log("Fee recipient:", cfg.feeRecipient);
        console.log("Credit bureau attestor:", cfg.attestor);
        console.log("Configured:", cfg.configure);
        if (cfg.configure && !cfg.transferToTg) {
            console.log(
                "NOTE: factory still deployer-owned. Set TRANSFER_TO_TG=true to hand to the TG:",
                cfg.realTg
            );
        }
        if (!cfg.configure) {
            console.log(
                "NOTE: PROD mode - run the governance MIP for the (TG-owned) config (spec 14.3)."
            );
        }
    }

    /// FORK-mode config: deployer owns the factory + registry here. Whitelist
    /// the USDC market and cbBTC collateral, set the lender-guard knobs +
    /// default params, and register the credit-bureau attestor. Split out to
    /// keep `run`'s stack shallow under optimizer_runs = 1.
    function _configure(
        CreditMarketplaceFactory factory,
        CreditTierRegistry tierRegistry,
        Addresses addresses,
        address attestor,
        address deployer
    ) internal {
        address mUsdc = addresses.getAddress("MOONWELL_USDC");
        address cbbtc = addresses.getAddress("cbBTC");
        address usdcOracle = addresses.getAddress("USDC_ORACLE");
        address btcFeed = addresses.getAddress("CHAINLINK_BTC_USD");

        // Staleness window first — the whitelist setters validate per-feed
        // staleness against it.
        factory.setStalenessWindow(STALENESS_WINDOW);
        factory.whitelistMToken(
            mUsdc,
            true,
            AggregatorV3Interface(usdcOracle),
            FEED_STALENESS
        );
        factory.whitelistCollateralToken(
            cbbtc,
            true,
            AggregatorV3Interface(btcFeed),
            FEED_STALENESS
        );

        // Lender guards (risk-report) + default loan params.
        factory.setMinOriginationLtvBufferBps(LTV_BUFFER_BPS);
        factory.setCollateralBufferBps(cbbtc, CBBTC_BUFFER_BPS);
        factory.setMinMoonwellHealthBufferBps(MOONWELL_HEALTH_BUFFER_BPS);
        factory.setDefaultParams(
            GRACE_PERIOD,
            OVER_SEIZURE_BPS,
            CONSECUTIVE_MISSES,
            MARKETPLACE_FEE_BPS
        );

        // Phase 2a: the registry's attestation signer.
        tierRegistry.setCreditBureauAttestor(attestor);

        // Extra markets/collateral (split into helpers to keep this frame
        // under the optimizer_runs = 1 stack limit).
        _configureCbethMarket(factory, addresses);
        _configureWbCoinCollateral(factory, addresses, deployer);
    }

    /// cbETH as an additional mToken *market* (lender pledges mcbETH), priced
    /// off the existing composite oracle. Not a collateral token, so no
    /// per-collateral buffer.
    function _configureCbethMarket(
        CreditMarketplaceFactory factory,
        Addresses addresses
    ) internal {
        factory.whitelistMToken(
            addresses.getAddress("MOONWELL_cbETH"),
            true,
            AggregatorV3Interface(addresses.getAddress("cbETH_COMPOSITE_ORACLE")),
            FEED_STALENESS
        );
    }

    /// wbCOIN collateral priced via a Chainlink Data Streams v10 adapter.
    /// FORK/local: deploy a MOCK verifier returning a static, settable COIN
    /// price (no DS API creds / DON signature needed) and seed the adapter
    /// through the real verify path so `_probeFeed` sees a fresh, positive
    /// answer at whitelist time. PROD points the adapter at the real verifier
    /// proxy (`0xDE1A…7387a`) instead — same adapter code.
    function _configureWbCoinCollateral(
        CreditMarketplaceFactory factory,
        Addresses addresses,
        address deployer
    ) internal {
        MockDataStreamsVerifierV10 mockVerifier = new MockDataStreamsVerifierV10(
            WBCOIN_DS_FEED_ID,
            WBCOIN_DEMO_PRICE,
            WBCOIN_MULTIPLIER
        );
        DataStreamsAggregatorAdapter adapter = new DataStreamsAggregatorAdapter(
            IVerifierProxy(address(mockVerifier)),
            WBCOIN_DS_FEED_ID,
            WBCOIN_PRICE_DECIMALS,
            deployer, // owner
            deployer // keeper
        );

        // Seed via the real verify→decode→gates→theoretical-price path.
        bytes32[3] memory ctx;
        adapter.verifyAndUpdate(abi.encode(ctx, bytes("")));

        factory.whitelistCollateralToken(
            addresses.getAddress("wbCOIN"),
            true,
            AggregatorV3Interface(address(adapter)),
            FEED_STALENESS
        );
        factory.setCollateralBufferBps(
            addresses.getAddress("wbCOIN"),
            WBCOIN_BUFFER_BPS
        );

        console.log("wbCOIN Data Streams adapter:", address(adapter));
        console.log("wbCOIN DS verifier (FORK mock stub):", address(mockVerifier));
    }
}

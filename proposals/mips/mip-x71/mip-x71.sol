//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Delegate} from "@protocol/MErc20Delegate.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MWethOwnerWrapper} from "@protocol/MWethOwnerWrapper.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, BASE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X71: internal cash accounting for all mToken markets
/// @notice Ports the fix from Venus PR #664 (THE market donation attack,
///         2026-03-15). MErc20.getCashPrior() read underlying.balanceOf, so a
///         direct transfer ("donation") raised the exchange rate without going
///         through mintAllowed — growing a holder's collateral past the supply
///         cap, including on markets frozen with a cap of 1.
///
///         The new MErc20Delegate / MWethDelegate track `internalCash`
///         (delegator slot 20, verified empty on every live market), updated
///         only by doTransferIn / doTransferOut and synced to balanceOf inside
///         _becomeImplementation, so each upgrade is a single atomic
///         `_setImplementation(new, true, "")` per market — the MIP-B02 /
///         MIP-E01 pattern.
///
///         Markets come from Comptroller.getAllMarkets() at fork state, and
///         each one's current implementation must equal the archived
///         MTOKEN_IMPLEMENTATION / MWETH_IMPLEMENTATION, so an unexpected
///         implementation fails build instead of being silently swapped.
///
///         Base MOONWELL_WETH is administered by MWETH_OWNER_WRAPPER (MIP-B54),
///         which had no _setImplementation passthrough. The wrapper proxy is
///         first upgraded (MRD_PROXY_ADMIN) to an implementation that adds
///         _setImplementation and _sweepExcessCash, then performs the swap.
///
/// how to generate calldata / run a standalone simulation against forks:
/*
export DO_DEPLOY=true
export DO_AFTER_DEPLOY=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/
/// forge script proposals/mips/mip-x71/mip-x71.sol:mipx71 --ffi -vvv
///
/// how to deploy the implementations (Ethereum: MErc20Delegate, MWethDelegate;
/// Base: + MWethOwnerWrapper; Optimism: MErc20Delegate, MWethDelegate).
/// deploy() opens a broadcast window per `new` on each fork; nothing else in
/// run() broadcasts (simulate/validate only prank and deal on the local
/// forks). Deployment runs must still use DO_RUN=false DO_VALIDATE=false so a
/// `--broadcast` run only deploys and never executes the governance flow:
/*
DO_DEPLOY=true DO_AFTER_DEPLOY=false DO_BUILD=false DO_RUN=false \
DO_TEARDOWN=false DO_VALIDATE=false DO_PRINT=false \
forge script proposals/mips/mip-x71/mip-x71.sol:mipx71 --ffi -vvv \
    --broadcast --account <deployer>
*/
/// then register the deployed addresses from
/// broadcast/multi/mip-x71.sol-latest/run.json in chains/<chainId>.json.
contract mipx71 is HybridProposalV2 {
    using ChainIds for uint256;

    string public constant override name = "MIP-X71";

    string internal constant MTOKEN_IMPL = "MTOKEN_IMPLEMENTATION";
    string internal constant MWETH_IMPL = "MWETH_IMPLEMENTATION";
    string internal constant MTOKEN_IMPL_DEPRECATED =
        "MTOKEN_IMPLEMENTATION_DEPRECATED_V1";
    string internal constant MWETH_IMPL_DEPRECATED =
        "MWETH_IMPLEMENTATION_DEPRECATED_V1";
    string internal constant WRAPPER_IMPL = "MWETH_OWNER_WRAPPER_IMPL";
    string internal constant WRAPPER_IMPL_DEPRECATED =
        "MWETH_OWNER_WRAPPER_IMPL_DEPRECATED_V1";

    /// @notice ERC1967 implementation slot, read to validate the wrapper upgrade
    bytes32 internal constant IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Base MWETH_OWNER_WRAPPER pre-upgrade state
    address internal preWrapperOwner;
    address internal preWrapperMToken;
    address internal preWrapperWeth;

    /// @notice pre-upgrade market state, captured in afterDeploy() (before
    /// build()/simulate()) and asserted unchanged in validate() to catch a
    /// storage collision or accidental reset during the swap
    struct MarketSnapshot {
        address admin;
        address pendingAdmin;
        address comptroller;
        address interestRateModel;
        address underlying;
        uint256 cash;
        uint256 exchangeRateStored;
        uint256 totalSupply;
        uint256 totalBorrows;
        uint256 totalReserves;
        uint256 reserveFactorMantissa;
    }

    /// @notice keyed by chain id first: Base and Optimism mweETH share an address
    mapping(uint256 chainId => mapping(address market => MarketSnapshot))
        internal snapshots;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x71/x71.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice mirrors Proposal.run() minus the top-level broadcast wrapper,
    /// following the other cross-chain proposals (mip-x43, mip-x64):
    /// deploy()/afterDeploy()/build()/validate() switch forks, which does not
    /// compose with an active vm.startBroadcast(). Keeps the descriptionUri
    /// injection so DO_PRINT calldata carries the pinned IPFS URI from mips.json.
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    /// @notice deploy the new MErc20Delegate and MWethDelegate on each chain,
    /// archiving the live implementations under *_DEPRECATED_V1 and promoting
    /// the new ones to the canonical names (MIP-X43 archive-then-promote), so
    /// MarketAdd templates pick up the fixed implementation for new markets.
    /// Idempotent: skipped once the deprecated name is registered.
    function deploy(Addresses addresses, address) public override {
        vm.selectFork(ETHEREUM_FORK_ID);
        _deployImplementations(addresses);

        vm.selectFork(BASE_FORK_ID);
        _deployImplementations(addresses);
        _deployWrapperImplementation(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _deployImplementations(addresses);

        vm.selectFork(primaryForkId());
    }

    function afterDeploy(Addresses addresses, address) public override {
        vm.selectFork(ETHEREUM_FORK_ID);
        _snapshotMarkets(addresses);

        vm.selectFork(BASE_FORK_ID);
        _snapshotMarkets(addresses);

        MWethOwnerWrapper wrapper = MWethOwnerWrapper(
            payable(addresses.getAddress("MWETH_OWNER_WRAPPER"))
        );
        preWrapperOwner = wrapper.owner();
        preWrapperMToken = address(wrapper.mToken());
        preWrapperWeth = address(wrapper.weth());

        vm.selectFork(OPTIMISM_FORK_ID);
        _snapshotMarkets(addresses);

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        vm.selectFork(ETHEREUM_FORK_ID);
        _buildUpgrades(addresses);

        vm.selectFork(BASE_FORK_ID);
        _buildUpgrades(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _buildUpgrades(addresses);

        vm.selectFork(primaryForkId());
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(ETHEREUM_FORK_ID);
        _validateMarkets(addresses);

        vm.selectFork(BASE_FORK_ID);
        _validateMarkets(addresses);
        _validateWrapper(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateMarkets(addresses);

        vm.selectFork(primaryForkId());
    }

    // ──────────────────────────────────────────────────────────────
    //                         DEPLOY
    // ──────────────────────────────────────────────────────────────

    /// @dev each `new` runs in its own broadcast window on the selected fork,
    /// so a `--broadcast` run sends exactly the CREATE txs; the `addresses`
    /// registry writes stay outside the window (they are calls to the
    /// in-script Addresses contract, not on-chain txs)
    function _deployImplementations(Addresses addresses) internal {
        if (!addresses.isAddressSet(MTOKEN_IMPL_DEPRECATED)) {
            vm.startBroadcast();
            MErc20Delegate mTokenLogic = new MErc20Delegate();
            vm.stopBroadcast();

            addresses.addAddress(
                MTOKEN_IMPL_DEPRECATED,
                addresses.getAddress(MTOKEN_IMPL)
            );
            addresses.changeAddress(MTOKEN_IMPL, address(mTokenLogic), true);
        }

        if (!addresses.isAddressSet(MWETH_IMPL_DEPRECATED)) {
            address oldMWethLogic = addresses.getAddress(MWETH_IMPL);
            address unwrapper = addresses.getAddress("WETH_UNWRAPPER");

            /// new delegate must reuse the live unwrapper
            require(
                MWethDelegate(oldMWethLogic).wethUnwrapper() == unwrapper,
                "MIP-X71: live mWETH unwrapper != WETH_UNWRAPPER"
            );

            vm.startBroadcast();
            MWethDelegate mWethLogic = new MWethDelegate(unwrapper);
            vm.stopBroadcast();

            addresses.addAddress(MWETH_IMPL_DEPRECATED, oldMWethLogic);
            addresses.changeAddress(MWETH_IMPL, address(mWethLogic), true);
        }
    }

    function _deployWrapperImplementation(Addresses addresses) internal {
        if (!addresses.isAddressSet(WRAPPER_IMPL_DEPRECATED)) {
            vm.startBroadcast();
            MWethOwnerWrapper wrapperLogic = new MWethOwnerWrapper();
            vm.stopBroadcast();

            addresses.addAddress(
                WRAPPER_IMPL_DEPRECATED,
                addresses.getAddress(WRAPPER_IMPL)
            );
            addresses.changeAddress(WRAPPER_IMPL, address(wrapperLogic), true);
        }
    }

    // ──────────────────────────────────────────────────────────────
    //                         SNAPSHOT
    // ──────────────────────────────────────────────────────────────

    function _snapshotMarkets(Addresses addresses) internal {
        MToken[] memory markets = Comptroller(
            addresses.getAddress("UNITROLLER")
        ).getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            MErc20Delegator market = MErc20Delegator(
                payable(address(markets[i]))
            );

            snapshots[block.chainid][address(market)] = MarketSnapshot({
                admin: market.admin(),
                pendingAdmin: market.pendingAdmin(),
                comptroller: address(market.comptroller()),
                interestRateModel: address(market.interestRateModel()),
                underlying: market.underlying(),
                cash: market.getCash(),
                exchangeRateStored: market.exchangeRateStored(),
                totalSupply: market.totalSupply(),
                totalBorrows: market.totalBorrows(),
                totalReserves: market.totalReserves(),
                reserveFactorMantissa: market.reserveFactorMantissa()
            });
        }
    }

    // ──────────────────────────────────────────────────────────────
    //                         BUILD
    // ──────────────────────────────────────────────────────────────

    function _buildUpgrades(Addresses addresses) internal {
        address oldMTokenLogic = addresses.getAddress(MTOKEN_IMPL_DEPRECATED);
        address oldMWethLogic = addresses.getAddress(MWETH_IMPL_DEPRECATED);
        address mWeth = addresses.getAddress("MOONWELL_WETH");

        MToken[] memory markets = Comptroller(
            addresses.getAddress("UNITROLLER")
        ).getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            MErc20Delegator market = MErc20Delegator(
                payable(address(markets[i]))
            );
            address current = market.implementation();

            if (address(market) == mWeth) {
                require(
                    current == oldMWethLogic,
                    "MIP-X71: MOONWELL_WETH on unexpected implementation"
                );
                _pushMWethUpgrade(addresses, market);
            } else {
                require(
                    current == oldMTokenLogic,
                    string.concat(
                        "MIP-X71: unexpected implementation on ",
                        market.symbol()
                    )
                );
                _pushAction(
                    address(market),
                    _setImplementationCalldata(
                        addresses.getAddress(MTOKEN_IMPL)
                    ),
                    string.concat(
                        "Upgrade ",
                        market.symbol(),
                        " to internal cash MErc20Delegate"
                    )
                );
            }
        }
    }

    function _pushMWethUpgrade(
        Addresses addresses,
        MErc20Delegator mWeth
    ) internal {
        address newLogic = addresses.getAddress(MWETH_IMPL);

        if (block.chainid != BASE_CHAIN_ID) {
            _pushAction(
                address(mWeth),
                _setImplementationCalldata(newLogic),
                "Upgrade MOONWELL_WETH to internal cash MWethDelegate"
            );
            return;
        }

        /// Base: MWETH_OWNER_WRAPPER is admin. Upgrade the wrapper to add the
        /// _setImplementation / _sweepExcessCash passthroughs, then swap
        /// through it.
        address wrapper = addresses.getAddress("MWETH_OWNER_WRAPPER");
        require(
            mWeth.admin() == wrapper,
            "MIP-X71: Base MOONWELL_WETH admin is not MWETH_OWNER_WRAPPER"
        );
        require(
            address(uint160(uint256(vm.load(wrapper, IMPLEMENTATION_SLOT)))) ==
                addresses.getAddress(WRAPPER_IMPL_DEPRECATED),
            "MIP-X71: MWETH_OWNER_WRAPPER on unexpected implementation"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                wrapper,
                addresses.getAddress(WRAPPER_IMPL)
            ),
            "Upgrade MWETH_OWNER_WRAPPER to add _setImplementation and _sweepExcessCash"
        );
        _pushAction(
            wrapper,
            _setImplementationCalldata(newLogic),
            "MWETH_OWNER_WRAPPER upgrades MOONWELL_WETH to internal cash MWethDelegate"
        );
    }

    function _setImplementationCalldata(
        address newLogic
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSignature(
                "_setImplementation(address,bool,bytes)",
                newLogic,
                true,
                ""
            );
    }

    // ──────────────────────────────────────────────────────────────
    //                         VALIDATE
    // ──────────────────────────────────────────────────────────────

    function _validateWrapper(Addresses addresses) internal view {
        address wrapperProxy = addresses.getAddress("MWETH_OWNER_WRAPPER");
        MWethOwnerWrapper wrapper = MWethOwnerWrapper(payable(wrapperProxy));

        assertEq(
            address(
                uint160(uint256(vm.load(wrapperProxy, IMPLEMENTATION_SLOT)))
            ),
            addresses.getAddress(WRAPPER_IMPL),
            "MWETH_OWNER_WRAPPER implementation not upgraded"
        );
        assertEq(wrapper.owner(), preWrapperOwner, "wrapper owner changed");
        assertEq(
            wrapper.owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "wrapper owner is not TEMPORAL_GOVERNOR"
        );
        assertEq(
            address(wrapper.mToken()),
            preWrapperMToken,
            "wrapper mToken changed"
        );
        assertEq(
            address(wrapper.weth()),
            preWrapperWeth,
            "wrapper weth changed"
        );
        assertEq(
            MErc20Delegator(payable(addresses.getAddress("MOONWELL_WETH")))
                .admin(),
            wrapperProxy,
            "MOONWELL_WETH admin is not MWETH_OWNER_WRAPPER"
        );
    }

    function _validateMarkets(Addresses addresses) internal view {
        address newMTokenLogic = addresses.getAddress(MTOKEN_IMPL);
        address newMWethLogic = addresses.getAddress(MWETH_IMPL);
        address mWeth = addresses.getAddress("MOONWELL_WETH");

        assertEq(
            MWethDelegate(newMWethLogic).wethUnwrapper(),
            addresses.getAddress("WETH_UNWRAPPER"),
            "new MWETH_IMPLEMENTATION unwrapper mismatch"
        );

        MToken[] memory markets = Comptroller(
            addresses.getAddress("UNITROLLER")
        ).getAllMarkets();
        assertGt(markets.length, 0, "no markets");

        for (uint256 i = 0; i < markets.length; i++) {
            MErc20Delegator market = MErc20Delegator(
                payable(address(markets[i]))
            );
            string memory symbol = market.symbol();
            MarketSnapshot memory pre = snapshots[block.chainid][
                address(market)
            ];

            assertEq(
                market.implementation(),
                address(market) == mWeth ? newMWethLogic : newMTokenLogic,
                string.concat(symbol, ": implementation not upgraded")
            );

            /// internal cash synced to the real balance at upgrade
            assertEq(
                MErc20Delegate(address(market)).internalCash(),
                IERC20(market.underlying()).balanceOf(address(market)),
                string.concat(symbol, ": internalCash != underlying balance")
            );

            /// upgrade leaves every storage-backed value untouched
            assertEq(
                market.admin(),
                pre.admin,
                string.concat(symbol, ": admin changed")
            );
            assertEq(
                market.pendingAdmin(),
                pre.pendingAdmin,
                string.concat(symbol, ": pendingAdmin changed")
            );
            assertEq(
                address(market.comptroller()),
                pre.comptroller,
                string.concat(symbol, ": comptroller changed")
            );
            assertEq(
                address(market.interestRateModel()),
                pre.interestRateModel,
                string.concat(symbol, ": interest rate model changed")
            );
            assertEq(
                market.underlying(),
                pre.underlying,
                string.concat(symbol, ": underlying changed")
            );
            assertEq(
                market.getCash(),
                pre.cash,
                string.concat(symbol, ": getCash changed")
            );
            assertEq(
                market.exchangeRateStored(),
                pre.exchangeRateStored,
                string.concat(symbol, ": exchangeRateStored changed")
            );
            assertEq(
                market.totalSupply(),
                pre.totalSupply,
                string.concat(symbol, ": totalSupply changed")
            );
            assertEq(
                market.totalBorrows(),
                pre.totalBorrows,
                string.concat(symbol, ": totalBorrows changed")
            );
            assertEq(
                market.totalReserves(),
                pre.totalReserves,
                string.concat(symbol, ": totalReserves changed")
            );
            assertEq(
                market.reserveFactorMantissa(),
                pre.reserveFactorMantissa,
                string.concat(symbol, ": reserveFactor changed")
            );
        }
    }
}

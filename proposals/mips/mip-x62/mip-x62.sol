//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X62: Upgrade WormholeBridgeAdapter to overpay-tolerant onchain quoting
/// @notice Deploys a fresh WormholeBridgeAdapter implementation on Base,
///         Optimism, and Ethereum, then upgrades the WORMHOLE_BRIDGE_ADAPTER_PROXY
///         behind each chain's ProxyAdmin. The new implementation relaxes the
///         onchain-quoter bridge path from requiring `msg.value == quote` to
///         `msg.value >= quote`, refunding any surplus to the caller. This lets
///         a caller that cannot predict the exact cost up front (e.g. a
///         governance proposal whose live quote drifts during the ~5-day voting
///         window) overfund with a buffer and be charged only the live quote.
///
///         Moonbeam is intentionally excluded: it has no onchain quoter
///         (`executorQuoterRouter == address(0)`), so the relaxed path is inert
///         there and its adapter is left on its current implementation.
contract mipx62 is HybridProposalV2 {
    using ChainIds for uint256;

    string public constant override name = "MIP-X62";

    /// @notice key for the new implementation deployed by this proposal
    string internal constant IMPL_KEY = "WORMHOLE_BRIDGE_ADAPTER_IMPL_V7";

    /// @notice destination chain used for the validation bridge() call.
    /// On Base we bridge to OP; on OP and Ethereum we bridge to Base.
    uint16 internal constant _BASE_DST_WH_ID = OPTIMISM_WORMHOLE_CHAIN_ID;
    uint16 internal constant _OP_DST_WH_ID = BASE_WORMHOLE_CHAIN_ID;
    uint16 internal constant _ETH_DST_WH_ID = BASE_WORMHOLE_CHAIN_ID;

    /// @notice mocked-user bridge amount used in `validate()`
    uint256 internal constant BRIDGE_AMOUNT = 1e18;

    /// @notice surplus the validation bridge over-sends above the live quote;
    /// the new implementation must refund exactly this back to the caller.
    uint256 internal constant OVERPAY = 0.01 ether;

    /// @notice pre-upgrade snapshot of storage-backed adapter state, keyed by
    /// fork id. Captured in afterDeploy() (before simulate() runs the upgrade)
    /// and asserted unchanged in validate(). The fix adds no storage, so an
    /// impl swap must leave every one of these untouched.
    struct AdapterSnapshot {
        address quoterAddress;
        address executorQuoterRouter;
        address executor;
        uint96 gasLimit;
    }

    mapping(uint256 forkId => AdapterSnapshot) internal snapshots;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x62/x62.md")
        );

        _setProposalDescription(proposalDescription);

        nonce = 2;
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice the ProxyAdmin that owns the WormholeBridgeAdapter proxy on a
    /// given chain. On Base and Optimism it is MRD_PROXY_ADMIN; on Ethereum the
    /// proxy is owned by the generic PROXY_ADMIN (MRD_PROXY_ADMIN resolves to a
    /// different, unrelated admin on Ethereum).
    function _proxyAdminKey(
        uint256 forkId
    ) internal pure returns (string memory) {
        if (forkId == ETHEREUM_FORK_ID) {
            return "PROXY_ADMIN";
        }
        return "MRD_PROXY_ADMIN";
    }

    /// @notice run() override mirroring the multi-chain deploy pattern (see
    /// mip-x53). The base HybridProposalV2 run() wraps deploy()+afterDeploy() in
    /// a single broadcast, but `vm.selectFork` is disallowed mid-broadcast and
    /// this proposal must switch forks to deploy on / snapshot every chain.
    /// Instead, deploy() broadcasts per-fork internally and afterDeploy() (a
    /// read-only snapshot) runs outside any broadcast.
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        vm.selectFork(primaryForkId());

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);
        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) validate(addresses, deployerAddress);
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    /// @notice deploy a fresh WormholeBridgeAdapter implementation on each
    /// quoter-enabled chain. Inert until governance points the proxy at it.
    /// Broadcasts per-fork: selectFork happens outside the broadcast window.
    function deploy(Addresses addresses, address) public override {
        uint256[3] memory forks = [
            BASE_FORK_ID,
            OPTIMISM_FORK_ID,
            ETHEREUM_FORK_ID
        ];

        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);
            if (!addresses.isAddressSet(IMPL_KEY)) {
                vm.startBroadcast();
                address impl = address(new WormholeBridgeAdapter());
                vm.stopBroadcast();
                addresses.addAddress(IMPL_KEY, impl);
            }
        }

        vm.selectFork(primaryForkId());
    }

    /// @notice snapshot pre-upgrade adapter state on each chain so validate()
    /// can prove the implementation swap left storage untouched. Runs before
    /// build()/simulate().
    function afterDeploy(Addresses addresses, address) public override {
        _snapshot(addresses, BASE_FORK_ID);
        _snapshot(addresses, OPTIMISM_FORK_ID);
        _snapshot(addresses, ETHEREUM_FORK_ID);

        vm.selectFork(primaryForkId());
    }

    function _snapshot(Addresses addresses, uint256 forkId) internal {
        vm.selectFork(forkId);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        snapshots[forkId] = AdapterSnapshot({
            quoterAddress: adapter.quoterAddress(),
            executorQuoterRouter: address(adapter.executorQuoterRouter()),
            executor: address(adapter.executor()),
            gasLimit: adapter.gasLimit()
        });
    }

    function build(Addresses addresses) public override {
        _pushUpgrade(addresses, BASE_FORK_ID, "Base");
        _pushUpgrade(addresses, OPTIMISM_FORK_ID, "Optimism");
        _pushUpgrade(addresses, ETHEREUM_FORK_ID, "Ethereum");

        vm.selectFork(primaryForkId());
    }

    /// @notice push the ProxyAdmin.upgrade action for one chain. The active
    /// fork determines the ActionType the HybridProposalV2 framework assigns.
    function _pushUpgrade(
        Addresses addresses,
        uint256 forkId,
        string memory chainName
    ) internal {
        vm.selectFork(forkId);
        _pushAction(
            addresses.getAddress(_proxyAdminKey(forkId)),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress(IMPL_KEY)
            ),
            string.concat(
                "Upgrade WormholeBridgeAdapter on ",
                chainName,
                " to the overpay-tolerant implementation"
            )
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        _validateChain(addresses, BASE_FORK_ID, "Base", _BASE_DST_WH_ID);
        _validateChain(addresses, OPTIMISM_FORK_ID, "Optimism", _OP_DST_WH_ID);
        _validateChain(addresses, ETHEREUM_FORK_ID, "Ethereum", _ETH_DST_WH_ID);

        vm.selectFork(primaryForkId());
    }

    /// @notice per-chain validation: implementation upgraded, storage state
    /// preserved, live quote positive, and an overpaying bridge() that must
    /// succeed and refund the surplus (the behavior this proposal ships).
    function _validateChain(
        Addresses addresses,
        uint256 forkId,
        string memory chainName,
        uint16 dstWormholeId
    ) internal {
        vm.selectFork(forkId);

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// 1. implementation upgraded to the new impl behind the proxy admin
        address proxyAdmin = addresses.getAddress(_proxyAdminKey(forkId));
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(address(adapter))
        );
        assertEq(
            actualImpl,
            addresses.getAddress(IMPL_KEY),
            string.concat(chainName, ": adapter not upgraded to new impl")
        );

        /// 2. storage-backed state unchanged by the swap
        AdapterSnapshot memory snap = snapshots[forkId];
        assertEq(
            adapter.quoterAddress(),
            snap.quoterAddress,
            string.concat(chainName, ": quoterAddress changed by upgrade")
        );
        assertEq(
            address(adapter.executorQuoterRouter()),
            snap.executorQuoterRouter,
            string.concat(chainName, ": executorQuoterRouter changed")
        );
        assertEq(
            address(adapter.executor()),
            snap.executor,
            string.concat(chainName, ": executor changed")
        );
        assertEq(
            adapter.gasLimit(),
            snap.gasLimit,
            string.concat(chainName, ": gasLimit changed by upgrade")
        );
        assertTrue(
            address(adapter.wormhole()) != address(0),
            string.concat(chainName, ": wormhole core not set")
        );

        /// 3. live onchain quote is positive (path is usable on this chain)
        uint256 cost = adapter.bridgeCost(dstWormholeId);
        assertGt(cost, 0, string.concat(chainName, ": bridgeCost returned 0"));

        /// 4. overpaying bridge() succeeds, burns tokens, and refunds surplus
        _runOverpayBridge(addresses, adapter, chainName, dstWormholeId, cost);
    }

    /// @notice fund a synthetic user with xWELL + (cost + OVERPAY) native, then
    /// bridge over-sending the surplus. The new implementation must accept
    /// `msg.value > cost`, burn the tokens, and refund exactly OVERPAY.
    function _runOverpayBridge(
        Addresses addresses,
        WormholeBridgeAdapter adapter,
        string memory chainName,
        uint16 dstWormholeId,
        uint256 cost
    ) internal {
        address user = address(0xBEEF);
        IERC20 xWell = IERC20(addresses.getAddress("xWELL_PROXY"));

        /// mint synthetic xWELL (deal adjusts balance + totalSupply)
        deal(address(xWell), user, BRIDGE_AMOUNT, true);

        /// fund the user with the live quote plus a surplus buffer
        vm.deal(user, cost + OVERPAY);

        uint256 userTokenBefore = xWell.balanceOf(user);
        uint256 totalSupplyBefore = xWell.totalSupply();

        vm.startPrank(user);
        xWell.approve(address(adapter), BRIDGE_AMOUNT);
        adapter.bridge{value: cost + OVERPAY}(
            uint256(dstWormholeId),
            BRIDGE_AMOUNT,
            user
        );
        vm.stopPrank();

        assertEq(
            userTokenBefore - xWell.balanceOf(user),
            BRIDGE_AMOUNT,
            string.concat(chainName, ": user xWELL not burned by bridge()")
        );
        assertEq(
            totalSupplyBefore - xWell.totalSupply(),
            BRIDGE_AMOUNT,
            string.concat(chainName, ": xWELL totalSupply not reduced")
        );
        assertEq(
            user.balance,
            OVERPAY,
            string.concat(chainName, ": surplus not refunded to caller")
        );
    }
}

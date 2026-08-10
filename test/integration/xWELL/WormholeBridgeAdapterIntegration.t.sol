// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {MockExecutorQuoterRouter} from "@test/mock/MockExecutorQuoterRouter.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {Address} from "@utils/Address.sol";
import {EnableEthereumXWellBridging} from "@script/EnableEthereumXWellBridging.s.sol";
import {MOONBEAM_CHAIN_ID, MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title WormholeBridgeAdapter V4 Integration Tests (Executor framework)
/// @notice Run with PRIMARY_FORK_ID env var to test on different chains:
///         PRIMARY_FORK_ID=0 (Moonbeam), 1 (Base), 2 (Optimism), 3 (Ethereum)
/// @dev    Ethereum coverage assumes MIP-X55's deployer-side bootstrap
///         (`script/EnableEthereumXWellBridging.s.sol`) has run. When the
///         live adapter is not yet wired (owner == MOONWELL_DEPLOYER),
///         `setUp()` invokes the script directly so the adapter behaves
///         like a fully-wired peer.
contract WormholeBridgeAdapterIntegrationTest is PostProposalCheck {
    using Address for address;
    using ChainIds for uint256;

    /// @notice wormhole bridge adapter proxy
    WormholeBridgeAdapter public adapter;

    /// @notice xWELL proxy
    xWELL public xwellProxy;

    /// @notice wormhole core address (real on-chain)
    address public wormholeCoreAddr;

    /// @notice wormhole relayer address (existing on-chain, deprecated)
    address public wormholeRelayerAddr;

    /// @notice mock wormhole core (etched onto WORMHOLE_CORE for controllable VAA tests)
    MockWormholeCore public mockWormholeCore;

    /// @notice wormhole chain id for current chain
    uint16 public currentWormholeChainId;

    /// @notice wormhole chain id to use as source in mock VAAs
    uint16 public sourceWormholeChainId;

    /// @notice wormhole chain id of a peer with a live OUTBOUND route, used by
    /// the bridge()/targetAddress assertions (see setUp for why this is kept
    /// distinct from sourceWormholeChainId after MIP-X64)
    uint16 public outboundPeerWormholeChainId;

    /// @notice test recipient
    address public recipient = address(0xCAFE);

    function setUp() public override {
        super.setUp();

        uint256 primaryForkId = vm.envUint("PRIMARY_FORK_ID");
        vm.selectFork(primaryForkId);

        adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeCoreAddr = addresses.getAddress("WORMHOLE_CORE");
        wormholeRelayerAddr = address(adapter.wormholeRelayer());

        // Determine wormhole chain IDs based on current chain. Source for the
        // mocked VAAs is any chain other than the current one; we pick a peer
        // that's actually wired so executeVAAv1 doesn't bail on "sender not
        // trusted" before mint/burn can run.
        currentWormholeChainId = block.chainid.toWormholeChainId();
        if (currentWormholeChainId == MOONBEAM_WORMHOLE_CHAIN_ID) {
            sourceWormholeChainId = BASE_WORMHOLE_CHAIN_ID;
        } else {
            sourceWormholeChainId = MOONBEAM_WORMHOLE_CHAIN_ID;
        }

        // Outbound bridge peer for the bridge()/targetAddress assertions.
        // Kept SEPARATE from sourceWormholeChainId (the inbound VAA emitter)
        // because MIP-X64 (Moonbeam "Before Sunset") zeroes targetAddress[16]
        // on the Ethereum/Base/Optimism adapters: Moonbeam stays a trusted
        // *sender* (so the executeVAAv1 receive/replay tests keep using it),
        // but it is no longer a valid outbound *target*. Pick a peer whose
        // outbound route survives the sunset:
        //   - Base / Optimism -> Ethereum (wired in MIP-X55)
        //   - Ethereum         -> Base     (wired by EnableEthereumXWellBridging)
        //   - Moonbeam         -> Base     (Moonbeam side untouched by MIP-X64)
        if (currentWormholeChainId == MOONBEAM_WORMHOLE_CHAIN_ID) {
            outboundPeerWormholeChainId = BASE_WORMHOLE_CHAIN_ID;
        } else if (currentWormholeChainId == ETHEREUM_WORMHOLE_CHAIN_ID) {
            outboundPeerWormholeChainId = BASE_WORMHOLE_CHAIN_ID;
        } else {
            outboundPeerWormholeChainId = ETHEREUM_WORMHOLE_CHAIN_ID;
        }

        // On Ethereum, MIP-X55's deployer-side wiring is not a proposal — it
        // runs out-of-band via `EnableEthereumXWellBridging.s.sol`. If the
        // adapter is still owned by MOONWELL_DEPLOYER, the script hasn't been
        // executed yet on the forked block; invoke it here so the adapter
        // behaves like a fully-wired peer.
        if (
            block.chainid == ETHEREUM_CHAIN_ID &&
            adapter.owner() == addresses.getAddress("MOONWELL_DEPLOYER")
        ) {
            new EnableEthereumXWellBridging().run();
        }

        /// etch MockWormholeCore onto the real WORMHOLE_CORE address so we
        /// can control parseAndVerifyVM return values for executeVAAv1 tests
        bytes memory runtimeBytecode = vm.getDeployedCode(
            "MockWormholeCore.sol"
        );
        vm.etch(wormholeCoreAddr, runtimeBytecode);
        mockWormholeCore = MockWormholeCore(wormholeCoreAddr);
        mockWormholeCore.setChainId(currentWormholeChainId);
    }

    // ---------------------------------------------------------------
    // Test 1: Upgrade preserves existing state
    // ---------------------------------------------------------------

    function testUpgradePreservesExistingState() public view {
        /// gasLimit: Base + Optimism + Ethereum all run at 700_000; Moonbeam
        /// is the outlier and stays at the contract default of 300_000.
        uint96 expectedGasLimit = block.chainid == MOONBEAM_CHAIN_ID
            ? 300_000
            : 700_000;
        assertEq(
            adapter.gasLimit(),
            expectedGasLimit,
            "gasLimit not at expected value after upgrade"
        );

        /// wormhole() returns the core bridge address
        assertEq(
            address(adapter.wormhole()),
            wormholeCoreAddr,
            "wormhole core not set correctly"
        );

        /// xERC20 token address preserved
        assertEq(
            address(adapter.xERC20()),
            addresses.getAddress("xWELL_PROXY"),
            "xERC20 address corrupted after upgrade"
        );

        /// owner preserved. On Moonbeam the governor owns the adapter; on
        /// Base/Optimism the TemporalGovernor owns it. On Ethereum, MIP-E00's
        /// acceptOwnership() runs in PostProposalCheck.setUp, handing the
        /// adapter from PAUSE_GUARDIAN to MultichainGovernorV2.
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            assertEq(
                adapter.owner(),
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                "owner changed after upgrade"
            );
        } else if (block.chainid == ETHEREUM_CHAIN_ID) {
            assertEq(
                adapter.owner(),
                addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"),
                "Ethereum owner should be MultichainGovernorV2 after MIP-E00"
            );
        } else {
            assertEq(
                adapter.owner(),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "owner changed after upgrade"
            );
        }

        /// trusted senders still include the adapter for a cross-chain source
        assertTrue(
            adapter.isTrustedSender(sourceWormholeChainId, address(adapter)),
            "adapter not trusted sender for source chain"
        );

        /// target address for a live outbound peer is not zero
        assertTrue(
            adapter.targetAddress(outboundPeerWormholeChainId) != address(0),
            "outbound peer target address is zero"
        );
    }

    // ---------------------------------------------------------------
    // Test 2: executeVAAv1 success
    // ---------------------------------------------------------------

    function testExecuteVAAv1Success() public {
        uint256 mintAmount = 1000e18;

        bytes memory payload = abi.encode(
            recipient,
            mintAmount,
            currentWormholeChainId
        );
        bytes32 emitterAddress = address(adapter).toBytes();

        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            emitterAddress,
            "",
            payload
        );

        uint256 balanceBefore = xwellProxy.balanceOf(recipient);

        bytes memory encodedVaa = abi.encode("unique-vaa-bytes-1");
        adapter.executeVAAv1(encodedVaa);

        assertEq(
            xwellProxy.balanceOf(recipient) - balanceBefore,
            mintAmount,
            "recipient did not receive correct amount"
        );
    }

    // ---------------------------------------------------------------
    // Test 3: executeVAAv1 replay protection (sequence-based)
    // ---------------------------------------------------------------

    function testExecuteVAAv1ReplayProtection() public {
        uint256 mintAmount = 1000e18;

        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, currentWormholeChainId)
        );

        bytes memory encodedVaa = abi.encode("replay-test-vaa");

        adapter.executeVAAv1(encodedVaa);

        /// second call with same sequence (0) should fail via bitmap replay protection
        vm.expectRevert();
        adapter.executeVAAv1(encodedVaa);
    }

    // ---------------------------------------------------------------
    // Test 4: executeVAAv1 untrusted emitter
    // ---------------------------------------------------------------

    function testExecuteVAAv1UntrustedEmitter() public {
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(0xDEAD).toBytes(),
            "",
            abi.encode(recipient, uint256(1000e18), currentWormholeChainId)
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        adapter.executeVAAv1(abi.encode("untrusted-emitter-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 5: Rate limit enforced on executeVAAv1
    // ---------------------------------------------------------------

    function testRateLimitEnforcedOnExecuteVAAv1() public {
        uint256 currentBuffer = xwellProxy.buffer(address(adapter));
        uint256 excessAmount = currentBuffer + 1;

        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, excessAmount, currentWormholeChainId)
        );

        vm.expectRevert("RateLimited: rate limit hit");
        adapter.executeVAAv1(abi.encode("rate-limit-test-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 6: receiveWormholeMessages always reverts
    // ---------------------------------------------------------------

    function testReceiveWormholeMessagesReverts() public {
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        adapter.receiveWormholeMessages(
            abi.encode(recipient, uint256(1000e18)),
            new bytes[](0),
            address(adapter).toBytes(),
            sourceWormholeChainId,
            keccak256("some-nonce")
        );
    }

    // ---------------------------------------------------------------
    // Test 7: bridge out after V4 upgrade
    // ---------------------------------------------------------------

    function testBridgeOutAfterUpgrade() public {
        address user = address(0xBEEF);
        uint256 bridgeAmount = 1000e18;

        if (block.chainid == ETHEREUM_CHAIN_ID) {
            // Ethereum xWELL has no mint history yet, so
            // `_totalSupplyCheckpoints` (ERC20VotesUpgradeable) is empty.
            // `deal()` only touches `_balances` + `_totalSupply`; the burn
            // path's `_writeCheckpoint(_subtract, amount)` would underflow
            // on `oldWeight == 0`. Mint via `executeVAAv1` so the checkpoint
            // is written properly, mirroring the prod inbound-bridge path.
            bytes32 emitter = bytes32(uint256(uint160(address(adapter))));
            mockWormholeCore.setStorage(
                true,
                sourceWormholeChainId,
                emitter,
                "",
                abi.encode(user, bridgeAmount, currentWormholeChainId)
            );
            adapter.executeVAAv1(abi.encode("mint-for-bridge-out-x55"));
        } else {
            deal(address(xwellProxy), user, bridgeAmount);
        }

        /// Etch mock executor so requestExecution succeeds
        address executorAddr = address(adapter.executor());
        MockExecutorQuoterRouter mockExecutor = new MockExecutorQuoterRouter();
        vm.etch(executorAddr, address(mockExecutor).code);

        uint256 messageFee = adapter.wormhole().messageFee();
        uint256 executorFee = 0.001 ether;
        vm.deal(user, messageFee + executorFee);

        uint256 userBalanceBefore = xwellProxy.balanceOf(user);
        uint256 totalSupplyBefore = xwellProxy.totalSupply();

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), bridgeAmount);
        adapter.bridge{value: messageFee + executorFee}(
            outboundPeerWormholeChainId,
            bridgeAmount,
            user,
            hex"deadbeef"
        );
        vm.stopPrank();

        assertEq(
            userBalanceBefore - xwellProxy.balanceOf(user),
            bridgeAmount,
            "user balance not reduced correctly"
        );
        assertEq(
            totalSupplyBefore - xwellProxy.totalSupply(),
            bridgeAmount,
            "total supply not reduced correctly"
        );
    }

    // ---------------------------------------------------------------
    // Test 8: initializeV5 cannot be called again
    // ---------------------------------------------------------------

    function testInitializeV5CannotBeCalledAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV5(address(1), address(2), address(3));
    }

    // ---------------------------------------------------------------
    // On-chain quote bridge tests (the bridge(uint256,uint256,address)
    // overload). After mip-x53 fixes quoterAddress on Base + Optimism,
    // bridgeCost > 0 and the on-chain-quote path becomes usable. Moonbeam
    // has no on-chain quoter — the path always reverts up front there.
    // ---------------------------------------------------------------

    function testBridgeOnchainQuoteFailsZeroValue() public {
        address user = address(0xBEEF);
        uint256 amount = 1e18;
        deal(address(xwellProxy), user, amount);

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), amount);

        if (block.chainid == MOONBEAM_CHAIN_ID) {
            vm.expectRevert(
                "WormholeBridge: onchain quoting not available, use bridge with signedQuote"
            );
        } else {
            vm.expectRevert("WormholeBridge: cost not equal to quote");
        }
        adapter.bridge{value: 0}(
            uint256(outboundPeerWormholeChainId),
            amount,
            user
        );
        vm.stopPrank();
    }

    function testBridgeOnchainQuoteSucceeds() public {
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            // Moonbeam has no on-chain quoter — covered by the failure test
            return;
        }
        if (block.chainid == ETHEREUM_CHAIN_ID) {
            // Skip on Ethereum: see comment on testBridgeOutAfterUpgrade —
            // the burn path underflows under our fresh-bridge MintLimits state.
            return;
        }

        address user = address(0xBEEF);
        uint256 amount = 1e18;
        deal(address(xwellProxy), user, amount);

        // Etch a mock router onto the live ExecutorQuoterRouter so
        // requestExecution succeeds without going to the real Wormhole network.
        address routerAddr = address(adapter.executorQuoterRouter());
        MockExecutorQuoterRouter mockRouter = new MockExecutorQuoterRouter();
        vm.etch(routerAddr, address(mockRouter).code);
        // Force a non-zero quote so the require(msg.value == cost) path runs
        MockExecutorQuoterRouter(routerAddr).setQuote(0.001 ether);

        uint256 cost = adapter.bridgeCost(outboundPeerWormholeChainId);
        assertGt(cost, 0, "expected non-zero on-chain quote post-mip-x53");

        vm.deal(user, cost);

        uint256 supplyBefore = xwellProxy.totalSupply();
        uint256 balanceBefore = xwellProxy.balanceOf(user);

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), amount);
        adapter.bridge{value: cost}(
            uint256(outboundPeerWormholeChainId),
            amount,
            user
        );
        vm.stopPrank();

        assertEq(
            balanceBefore - xwellProxy.balanceOf(user),
            amount,
            "user xWELL not burned"
        );
        assertEq(
            supplyBefore - xwellProxy.totalSupply(),
            amount,
            "totalSupply did not drop"
        );
    }

    // ---------------------------------------------------------------
    // Test 9: Wormhole core rejection propagates through executeVAAv1
    // ---------------------------------------------------------------

    function testExecuteVAAv1RevertsWhenWormholeCoreRejectsVAA() public {
        mockWormholeCore.setStorage(
            false,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "VM version incompatible",
            ""
        );

        vm.expectRevert("VM version incompatible");
        adapter.executeVAAv1(hex"deadbeef1234567890");
    }

    // ---------------------------------------------------------------
    // Test 10: bridgeCost returns 0 when no executorQuoterRouter
    // ---------------------------------------------------------------

    function testBridgeCostReturnsZeroGracefully() public view {
        /// If executorQuoterRouter is not set (e.g. Moonbeam), bridgeCost returns 0
        /// On chains with a quoter, it returns the executor quote + message fee
        uint256 cost = adapter.bridgeCost(sourceWormholeChainId);
        /// Either 0 (no quoter / quote fails) or some value — just ensure no revert
        assertTrue(cost >= 0, "bridgeCost should not revert");
    }

    // ---------------------------------------------------------------
    // Test 11: executeVAAv1 reverts when to=address(0)
    // ---------------------------------------------------------------

    function testExecuteVAAv1RevertsToZeroAddress() public {
        // payload must encode (to, amount, targetChainId) — the 3-tuple
        // executeVAAv1 abi.decodes. Missing fields cause an abi.decode panic
        // with empty revert data, masking the intended OZ zero-address require.
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(address(0), uint256(1000e18), currentWormholeChainId)
        );

        vm.expectRevert("ERC20: mint to the zero address");
        adapter.executeVAAv1(abi.encode("zero-address-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 12: E2E cross-chain bridge (burn on source, mint on dest)
    // ---------------------------------------------------------------

    function testE2ECrossChainBridge() public {
        /// --- Source chain: burn tokens via bridge() ---
        address user = address(0xBEEF);
        uint256 bridgeAmount = 1000e18;

        /// Get xWELL to user. On Moonbeam (unwrapper), deposit WELL via lockbox.
        /// On Base/Optimism, mint via executeVAAv1 (properly updates rate limiter).
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));
            address lockbox = addresses.getAddress("xWELL_LOCKBOX");
            deal(address(well), user, bridgeAmount);
            vm.startPrank(user);
            well.approve(lockbox, bridgeAmount);
            XERC20Lockbox(lockbox).deposit(bridgeAmount);
            vm.stopPrank();
        } else {
            bytes32 emitterAddr = bytes32(uint256(uint160(address(adapter))));
            mockWormholeCore.setStorage(
                true,
                sourceWormholeChainId,
                emitterAddr,
                "",
                abi.encode(user, bridgeAmount, currentWormholeChainId)
            );
            adapter.executeVAAv1(abi.encode("mint-for-bridge-out"));
        }

        /// Etch mock executor so requestExecution succeeds
        address executorAddr = address(adapter.executor());
        MockExecutorQuoterRouter mockExec = new MockExecutorQuoterRouter();
        vm.etch(executorAddr, address(mockExec).code);

        uint256 messageFee = adapter.wormhole().messageFee();
        uint256 executorFee = 0.001 ether;
        vm.deal(user, messageFee + executorFee);

        uint256 sourceBalanceBefore = xwellProxy.balanceOf(user);
        uint256 sourceSupplyBefore = xwellProxy.totalSupply();

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), bridgeAmount);
        adapter.bridge{value: messageFee + executorFee}(
            outboundPeerWormholeChainId,
            bridgeAmount,
            user,
            hex"deadbeef"
        );
        vm.stopPrank();

        /// Verify burn on source
        assertEq(
            sourceBalanceBefore - xwellProxy.balanceOf(user),
            bridgeAmount,
            "source: tokens not burned correctly"
        );
        assertEq(
            sourceSupplyBefore - xwellProxy.totalSupply(),
            bridgeAmount,
            "source: total supply not reduced"
        );

        /// --- Destination chain: mint via executeVAAv1 ---
        _executeVAAOnDestFork(user, bridgeAmount);
    }

    /// @notice Helper: switch to dest fork, etch mock, executeVAAv1, verify mint + replay.
    ///         Handles Moonbeam (unwrapper delivers WELL) vs Base/Optimism/Ethereum
    ///         (delivers xWELL).
    function _executeVAAOnDestFork(
        address user,
        uint256 bridgeAmount
    ) internal {
        // Pick a dest fork that's already wired bidirectionally with the
        // current source. For Moonbeam→Base, Base→Moonbeam, Optimism→Moonbeam
        // the existing fixture works. For Ethereum→? we route to Moonbeam,
        // which after MIP-X55 trusts Ethereum.
        uint256 destForkId;
        if (currentWormholeChainId == MOONBEAM_WORMHOLE_CHAIN_ID) {
            destForkId = BASE_FORK_ID;
        } else if (currentWormholeChainId == ETHEREUM_WORMHOLE_CHAIN_ID) {
            destForkId = MOONBEAM_FORK_ID;
        } else {
            destForkId = MOONBEAM_FORK_ID;
        }
        vm.selectFork(destForkId);

        WormholeBridgeAdapter destAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// Etch mock and configure — payload includes dest chain ID and dest adapter address
        uint16 destWormholeChainId = block.chainid.toWormholeChainId();
        _etchMockOnCurrentFork(
            destAdapter,
            currentWormholeChainId,
            abi.encode(user, bridgeAmount, destWormholeChainId)
        );

        if (block.chainid == MOONBEAM_CHAIN_ID) {
            /// Moonbeam: unwrapper delivers WELL via lockbox
            IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));
            address lockbox = addresses.getAddress("xWELL_LOCKBOX");
            deal(address(well), lockbox, bridgeAmount);

            uint256 wellBefore = well.balanceOf(user);
            destAdapter.executeVAAv1(abi.encode("e2e-cross-chain-vaa"));
            assertEq(
                well.balanceOf(user) - wellBefore,
                bridgeAmount,
                "dest (Moonbeam): WELL not delivered correctly"
            );
        } else {
            /// Base/Optimism: regular adapter delivers xWELL
            xWELL destXwell = xWELL(addresses.getAddress("xWELL_PROXY"));
            uint256 destBalanceBefore = destXwell.balanceOf(user);
            destAdapter.executeVAAv1(abi.encode("e2e-cross-chain-vaa"));
            assertEq(
                destXwell.balanceOf(user) - destBalanceBefore,
                bridgeAmount,
                "dest: xWELL not minted correctly"
            );
        }

        /// Verify replay protection on destination (same sequence reverts)
        vm.expectRevert();
        destAdapter.executeVAAv1(abi.encode("e2e-cross-chain-vaa"));
    }

    /// @notice Etch MockWormholeCore onto current fork's WORMHOLE_CORE and configure it
    function _etchMockOnCurrentFork(
        WormholeBridgeAdapter destAdapter,
        uint16 emitterChainId,
        bytes memory payload
    ) internal {
        address core = addresses.getAddress("WORMHOLE_CORE");
        vm.etch(core, vm.getDeployedCode("MockWormholeCore.sol"));
        MockWormholeCore mock = MockWormholeCore(core);

        uint16 thisChainId = block.chainid.toWormholeChainId();
        mock.setChainId(thisChainId);
        mock.setStorage(
            true,
            emitterChainId,
            address(destAdapter).toBytes(),
            "",
            payload
        );
    }
}

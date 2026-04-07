// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Address} from "@utils/Address.sol";
import {MOONBEAM_CHAIN_ID, MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title WormholeBridgeAdapter V3 Integration Tests
/// @notice Run with PRIMARY_FORK_ID env var to test on different chains:
///         PRIMARY_FORK_ID=0 (Moonbeam), 1 (Base), 2 (Optimism)
contract WormholeBridgeAdapterIntegrationTest is PostProposalCheck {
    using Address for address;
    using ChainIds for uint256;

    /// @notice wormhole bridge adapter proxy
    WormholeBridgeAdapter public adapter;

    /// @notice xWELL proxy
    xWELL public xwellProxy;

    /// @notice wormhole core address (real on-chain)
    address public wormholeCoreAddr;

    /// @notice wormhole relayer address (existing on-chain)
    address public wormholeRelayerAddr;

    /// @notice mock wormhole core (etched onto WORMHOLE_CORE for controllable VAA tests)
    MockWormholeCore public mockWormholeCore;

    /// @notice wormhole chain id for current chain
    uint16 public currentWormholeChainId;

    /// @notice wormhole chain id to use as source in mock VAAs
    uint16 public sourceWormholeChainId;

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

        // Determine wormhole chain IDs based on current chain
        currentWormholeChainId = block.chainid.toWormholeChainId();
        sourceWormholeChainId = currentWormholeChainId ==
            MOONBEAM_WORMHOLE_CHAIN_ID
            ? BASE_WORMHOLE_CHAIN_ID
            : MOONBEAM_WORMHOLE_CHAIN_ID;

        /// etch MockWormholeCore onto the real WORMHOLE_CORE address so we
        /// can control parseAndVerifyVM return values for processVAA tests
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
        /// wormholeRelayer still returns the old relayer address
        assertFalse(
            address(adapter.wormholeRelayer()) == address(0),
            "wormholeRelayer should not be zero after upgrade"
        );

        /// gasLimit is still 300_000
        assertEq(adapter.gasLimit(), 300_000, "gasLimit changed after upgrade");

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

        /// owner preserved
        string memory ownerKey = block.chainid == MOONBEAM_CHAIN_ID
            ? "MULTICHAIN_GOVERNOR_PROXY"
            : "TEMPORAL_GOVERNOR";
        assertEq(
            adapter.owner(),
            addresses.getAddress(ownerKey),
            "owner changed after upgrade"
        );

        /// trusted senders still include the adapter for a cross-chain source
        assertTrue(
            adapter.isTrustedSender(sourceWormholeChainId, address(adapter)),
            "adapter not trusted sender for source chain"
        );

        /// target address for source chain is not zero
        assertTrue(
            adapter.targetAddress(sourceWormholeChainId) != address(0),
            "source chain target address is zero"
        );
    }

    // ---------------------------------------------------------------
    // Test 2: processVAA success
    // ---------------------------------------------------------------

    function testProcessVAASuccess() public {
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

        bytes memory signedVAA = abi.encode("unique-vaa-bytes-1");
        adapter.processVAA(signedVAA);

        assertEq(
            xwellProxy.balanceOf(recipient) - balanceBefore,
            mintAmount,
            "recipient did not receive correct amount"
        );

        assertTrue(
            adapter.processedVAAHashes(keccak256(signedVAA)),
            "VAA hash not marked as processed"
        );
    }

    // ---------------------------------------------------------------
    // Test 3: processVAA replay protection
    // ---------------------------------------------------------------

    function testProcessVAAReplayProtection() public {
        uint256 mintAmount = 1000e18;

        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, currentWormholeChainId)
        );

        bytes memory signedVAA = abi.encode("replay-test-vaa");

        adapter.processVAA(signedVAA);

        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        adapter.processVAA(signedVAA);
    }

    // ---------------------------------------------------------------
    // Test 4: processVAA untrusted emitter
    // ---------------------------------------------------------------

    function testProcessVAAUntrustedEmitter() public {
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(0xDEAD).toBytes(),
            "",
            abi.encode(recipient, uint256(1000e18), currentWormholeChainId)
        );

        vm.expectRevert("WormholeBridgeAdapter: untrusted emitter");
        adapter.processVAA(abi.encode("untrusted-emitter-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 5: Multiple processVAA calls with different VAAs succeed,
    //         replay of either reverts
    // ---------------------------------------------------------------

    function testProcessVAAMultipleMintsThenReplay() public {
        uint256 mintAmount = 500e18;

        uint256 balanceBefore = xwellProxy.balanceOf(recipient);

        /// --- Step 1: first processVAA ---
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, currentWormholeChainId)
        );

        bytes memory signedVAA1 = abi.encode("first-vaa");
        adapter.processVAA(signedVAA1);

        uint256 balanceAfterFirst = xwellProxy.balanceOf(recipient);
        assertEq(
            balanceAfterFirst - balanceBefore,
            mintAmount,
            "first processVAA did not mint correctly"
        );

        /// --- Step 2: second processVAA with different bytes ---
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, currentWormholeChainId)
        );

        bytes memory signedVAA2 = abi.encode("second-vaa");
        adapter.processVAA(signedVAA2);

        assertEq(
            xwellProxy.balanceOf(recipient) - balanceAfterFirst,
            mintAmount,
            "second processVAA did not mint correctly"
        );

        /// --- Step 3: replay of either VAA reverts ---
        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        adapter.processVAA(signedVAA1);

        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        adapter.processVAA(signedVAA2);
    }

    // ---------------------------------------------------------------
    // Test 6: Rate limit enforced on processVAA
    // ---------------------------------------------------------------

    function testRateLimitEnforcedOnProcessVAA() public {
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
        adapter.processVAA(abi.encode("rate-limit-test-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 7: receiveWormholeMessages reverts after V3 upgrade
    // ---------------------------------------------------------------

    function testReceiveWormholeMessagesReverts() public {
        vm.prank(wormholeRelayerAddr);
        vm.expectRevert("WormholeBridgeAdapter: relayer disabled");
        adapter.receiveWormholeMessages(
            abi.encode(recipient, uint256(1000e18)),
            new bytes[](0),
            address(adapter).toBytes(),
            sourceWormholeChainId,
            keccak256("some-nonce")
        );
    }

    // ---------------------------------------------------------------
    // Test 8: bridge out after V3 upgrade
    // ---------------------------------------------------------------

    function testBridgeOutAfterUpgrade() public {
        address user = address(0xBEEF);
        uint256 bridgeAmount = 1000e18;

        deal(address(xwellProxy), user, bridgeAmount);

        uint256 cost = adapter.bridgeCost(sourceWormholeChainId);
        vm.deal(user, cost);

        uint256 userBalanceBefore = xwellProxy.balanceOf(user);
        uint256 totalSupplyBefore = xwellProxy.totalSupply();

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), bridgeAmount);
        adapter.bridge{value: cost}(sourceWormholeChainId, bridgeAmount, user);
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
    // Test 9: initializeV3 cannot be called again
    // ---------------------------------------------------------------

    function testInitializeV3CannotBeCalledAgain() public {
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(wormholeCoreAddr);
    }

    // ---------------------------------------------------------------
    // Test 10: Wormhole core rejection propagates through processVAA
    // ---------------------------------------------------------------

    function testProcessVAARevertsWhenWormholeCoreRejectsVAA() public {
        /// Configure the mock to return valid=false, simulating the real
        /// Wormhole core rejecting a junk/forged/tampered VAA.
        mockWormholeCore.setStorage(
            false,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "VM version incompatible",
            ""
        );

        vm.expectRevert("VM version incompatible");
        adapter.processVAA(hex"deadbeef1234567890");
    }

    // ---------------------------------------------------------------
    // Test 11: bridgeCost returns 0 gracefully when relayer is dead
    // ---------------------------------------------------------------

    function testBridgeCostReturnsZeroGracefully() public {
        /// Nuke the relayer to simulate it being deprecated / self-destructed.
        vm.etch(wormholeRelayerAddr, hex"fe");

        /// after the relayer is dead, bridgeCost must not revert
        uint256 cost = adapter.bridgeCost(sourceWormholeChainId);
        assertEq(
            cost,
            0,
            "bridgeCost should return 0 gracefully via try-catch"
        );
    }

    // ---------------------------------------------------------------
    // Test 12: processVAA reverts when to=address(0)
    // ---------------------------------------------------------------

    function testProcessVAARevertsToZeroAddress() public {
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(address(0), uint256(1000e18), currentWormholeChainId)
        );

        vm.expectRevert("ERC20: mint to the zero address");
        adapter.processVAA(abi.encode("zero-address-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 13: E2E cross-chain bridge (burn on source, mint on dest)
    // ---------------------------------------------------------------

    function testE2ECrossChainBridge() public {
        /// --- Source chain: burn tokens via bridge() ---
        address user = address(0xBEEF);
        uint256 bridgeAmount = 1000e18;

        deal(address(xwellProxy), user, bridgeAmount);

        uint256 cost = adapter.bridgeCost(sourceWormholeChainId);
        vm.deal(user, cost);

        uint256 sourceBalanceBefore = xwellProxy.balanceOf(user);
        uint256 sourceSupplyBefore = xwellProxy.totalSupply();

        vm.startPrank(user);
        xwellProxy.approve(address(adapter), bridgeAmount);
        adapter.bridge{value: cost}(sourceWormholeChainId, bridgeAmount, user);
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

        /// --- Destination chain: mint via processVAA ---
        _processVAAOnDestFork(user, bridgeAmount);
    }

    /// @notice Helper: switch to dest fork, etch mock, processVAA, verify mint + replay
    function _processVAAOnDestFork(
        address user,
        uint256 bridgeAmount
    ) internal {
        uint256 destForkId = currentWormholeChainId ==
            MOONBEAM_WORMHOLE_CHAIN_ID
            ? BASE_FORK_ID
            : MOONBEAM_FORK_ID;
        vm.selectFork(destForkId);

        WormholeBridgeAdapter destAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        xWELL destXwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        /// Etch mock and configure
        _etchMockOnCurrentFork(
            destAdapter,
            currentWormholeChainId,
            abi.encode(user, bridgeAmount, block.chainid.toWormholeChainId())
        );

        uint256 destBalanceBefore = destXwell.balanceOf(user);

        destAdapter.processVAA(abi.encode("e2e-cross-chain-vaa"));

        assertEq(
            destXwell.balanceOf(user) - destBalanceBefore,
            bridgeAmount,
            "dest: tokens not minted correctly"
        );

        /// Verify replay protection on destination
        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        destAdapter.processVAA(abi.encode("e2e-cross-chain-vaa"));
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

    // ---------------------------------------------------------------
    // Test 14: Cross-chain replay rejection (targetChainId mismatch)
    // ---------------------------------------------------------------

    /// @notice A VAA destined for chain A must NOT be processable on chain B.
    ///         The payload includes targetChainId which is validated against
    ///         wormhole.chainId() on the receiving chain. Without this check,
    ///         an attacker could replay the same VAA on every chain the protocol
    ///         is deployed to, multiplying minted tokens.
    function testProcessVAARevertsWrongTargetChain() public {
        uint256 mintAmount = 1000e18;

        /// Explicitly re-set chainId on the mock to ensure it returns
        /// currentWormholeChainId (guards against stale storage after vm.etch)
        mockWormholeCore.setChainId(currentWormholeChainId);

        /// Encode payload targeting a DIFFERENT chain (sourceWormholeChainId != currentWormholeChainId)
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, sourceWormholeChainId) /// wrong target chain
        );

        vm.expectRevert("WormholeBridgeAdapter: invalid target chain");
        adapter.processVAA(abi.encode("wrong-target-chain-vaa"));
    }

    // ---------------------------------------------------------------
    // Test 15: Cross-chain replay — full multi-fork scenario
    // ---------------------------------------------------------------

    /// @notice Simulate the exact attack: bridge to Base, then try to replay
    ///         the same VAA on Moonbeam. The VAA has targetChainId=Base so
    ///         Moonbeam must reject it.
    function testCrossChainReplayRejectedOnDifferentFork() public {
        uint256 mintAmount = 1000e18;

        /// --- Step 1: Process VAA successfully on current chain ---
        mockWormholeCore.setStorage(
            true,
            sourceWormholeChainId,
            address(adapter).toBytes(),
            "",
            abi.encode(recipient, mintAmount, currentWormholeChainId)
        );

        uint256 balanceBefore = xwellProxy.balanceOf(recipient);
        adapter.processVAA(abi.encode("cross-chain-replay-vaa"));

        assertEq(
            xwellProxy.balanceOf(recipient) - balanceBefore,
            mintAmount,
            "legitimate mint should succeed"
        );

        /// --- Step 2: Switch to a different fork and try to replay ---
        _replayOnOtherForkReverts(mintAmount);
    }

    /// @notice Helper: switch to other fork, etch mock with wrong targetChainId, expect revert
    function _replayOnOtherForkReverts(uint256 mintAmount) internal {
        uint256 otherForkId = currentWormholeChainId ==
            MOONBEAM_WORMHOLE_CHAIN_ID
            ? BASE_FORK_ID
            : MOONBEAM_FORK_ID;
        vm.selectFork(otherForkId);

        WormholeBridgeAdapter otherAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// Use currentWormholeChainId as emitter chain — the other fork
        /// trusts the adapter from the original fork's chain. For example,
        /// if original=Base(30) and other=Moonbeam, Moonbeam trusts Base(30).
        _etchMockOnCurrentFork(
            otherAdapter,
            currentWormholeChainId, /// emitter from original fork (trusted by other fork)
            abi.encode(recipient, mintAmount, currentWormholeChainId) /// wrong target
        );

        /// This must revert because targetChainId (original chain) != otherChainId
        vm.expectRevert("WormholeBridgeAdapter: invalid target chain");
        otherAdapter.processVAA(abi.encode("cross-chain-replay-vaa"));
    }
}

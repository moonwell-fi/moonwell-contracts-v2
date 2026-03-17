// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IExecutor} from "@protocol/wormhole/IExecutorQuoterRouter.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {UpgradeWormholeBridgeAdapterEthereum} from "@script/UpgradeWormholeBridgeAdapterEthereum.s.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/// @notice Integration test for xWELL WormholeBridgeAdapter after Executor migration.
/// Inherits PostProposalCheck so mip-x48 runs in setUp(), upgrading the adapter on
/// Moonbeam/Base/Optimism. Inherits UpgradeWormholeBridgeAdapterEthereum to conditionally
/// upgrade the Ethereum adapter if V3 is not yet initialized on-chain.
contract xWellExecutorIntegrationTest is
    PostProposalCheck,
    UpgradeWormholeBridgeAdapterEthereum
{
    /// Per-chain adapter addresses (resolved on respective forks)
    address public adapterAddrMoonbeam;
    address public adapterAddrBase;
    address public adapterAddrOptimism;
    address public adapterAddrEthereum;

    /// Per-chain xWELL addresses
    address public xwellAddrMoonbeam;
    address public xwellAddrBase;
    address public xwellAddrOptimism;
    address public xwellAddrEthereum;

    /// Per-chain core bridge addresses (read after V3 init)
    address public coreBridgeMoonbeam;
    address public coreBridgeBase;
    address public coreBridgeOptimism;
    address public coreBridgeEthereum;

    /// Per-chain executor addresses (for off-chain quote mocking)
    address public executorMoonbeam;
    address public executorBase;
    address public executorOptimism;
    address public executorEthereum;

    address user = address(0x123);
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    event BridgedIn(
        uint256 indexed srcChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    event TokensSent(
        uint16 indexed dstChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    function setUp() public override {
        super.setUp();

        // Moonbeam
        vm.selectFork(MOONBEAM_FORK_ID);
        adapterAddrMoonbeam = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        xwellAddrMoonbeam = addresses.getAddress("xWELL_PROXY");
        coreBridgeMoonbeam = address(
            WormholeBridgeAdapter(adapterAddrMoonbeam).coreBridge()
        );
        executorMoonbeam = address(
            WormholeBridgeAdapter(adapterAddrMoonbeam).executor()
        );

        // Base
        vm.selectFork(BASE_FORK_ID);
        adapterAddrBase = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        xwellAddrBase = addresses.getAddress("xWELL_PROXY");
        coreBridgeBase = address(
            WormholeBridgeAdapter(adapterAddrBase).coreBridge()
        );
        executorBase = address(
            WormholeBridgeAdapter(adapterAddrBase).executor()
        );

        // Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        adapterAddrOptimism = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        xwellAddrOptimism = addresses.getAddress("xWELL_PROXY");
        coreBridgeOptimism = address(
            WormholeBridgeAdapter(adapterAddrOptimism).coreBridge()
        );
        executorOptimism = address(
            WormholeBridgeAdapter(adapterAddrOptimism).executor()
        );

        // Ethereum — upgrade if V3 not yet initialized
        vm.selectFork(ETHEREUM_FORK_ID);
        adapterAddrEthereum = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        xwellAddrEthereum = addresses.getAddress("xWELL_PROXY");

        /// Old impl doesn't have wormholeChainId(), so try/catch
        try
            WormholeBridgeAdapter(adapterAddrEthereum).wormholeChainId()
        returns (uint16 chainId) {
            if (chainId == 0) _upgradeEthereumAdapter();
        } catch {
            _upgradeEthereumAdapter();
        }
        coreBridgeEthereum = address(
            WormholeBridgeAdapter(adapterAddrEthereum).coreBridge()
        );
        executorEthereum = address(
            WormholeBridgeAdapter(adapterAddrEthereum).executor()
        );
    }

    /// @notice Deploy new impl and upgradeAndCall on Ethereum fork
    function _upgradeEthereumAdapter() internal {
        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address proxyAdminOwner = ProxyAdmin(proxyAdmin).owner();

        vm.startPrank(proxyAdminOwner);
        address newImpl = address(new WormholeBridgeAdapter());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(adapterAddrEthereum),
            newImpl,
            abi.encodeWithSignature(
                "initializeV3(address,address,address,address,uint16)",
                addresses.getAddress("WORMHOLE_CORE"),
                addresses.getAddress("WORMHOLE_EXECUTOR"),
                address(0),
                address(0),
                ETHEREUM_WORMHOLE_CHAIN_ID
            )
        );
        vm.stopPrank();
    }

    /// --------------------------------------------------------
    /// ---------------------- Helpers -------------------------
    /// --------------------------------------------------------

    function _mockParseAndVerifyVM(
        address coreBridgeAddr,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        bytes memory payload
    ) internal {
        IWormhole.VM memory wormholeVm;
        wormholeVm.emitterChainId = emitterChainId;
        wormholeVm.emitterAddress = emitterAddress;
        wormholeVm.sequence = sequence;
        wormholeVm.payload = payload;
        wormholeVm.consistencyLevel = 200;

        vm.mockCall(
            coreBridgeAddr,
            abi.encodeWithSelector(IWormhole.parseAndVerifyVM.selector),
            abi.encode(wormholeVm, true, "")
        );
    }

    function _bridgeInViaVaa(
        address adapterAddr,
        address coreBridgeAddr,
        address to,
        uint256 amount,
        uint64 sequence,
        uint16 srcChainId
    ) internal {
        bytes32 emitterAddr = bytes32(uint256(uint160(adapterAddr)));
        bytes memory payload = abi.encode(to, amount);

        _mockParseAndVerifyVM(
            coreBridgeAddr,
            srcChainId,
            emitterAddr,
            sequence,
            payload
        );

        WormholeBridgeAdapter(adapterAddr).executeVAAv1(abi.encode(sequence));
        vm.clearMockedCalls();
    }

    /// @notice Mock the executor's requestExecution (off-chain quote overload)
    /// so bridge-out with signedQuote succeeds on forks without a real signed quote.
    function _mockExecutorRequestExecution(address executorAddr) internal {
        vm.mockCall(
            executorAddr,
            abi.encodeWithSelector(IExecutor.requestExecution.selector),
            abi.encode()
        );
    }

    function _boundMintAmount(
        address xwellAddr,
        address adapterAddr,
        uint256 mintAmount
    ) internal view returns (uint256) {
        uint256 buffer = xWELL(xwellAddr).buffer(adapterAddr);
        return _bound(mintAmount, 1, buffer);
    }

    /// ========================================================
    /// ================== Moonbeam Tests ======================
    /// ========================================================

    function testMoonbeamSetupAfterUpgrade() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrMoonbeam
        );

        assertEq(
            address(adapter.coreBridge()),
            coreBridgeMoonbeam,
            "Moonbeam: coreBridge not set"
        );
        assertTrue(
            address(adapter.executor()) != address(0),
            "Moonbeam: executor not set"
        );
        assertEq(
            adapter.wormholeChainId(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            "Moonbeam: wormholeChainId not set"
        );
        assertEq(
            address(adapter.wormholeRelayer()),
            coreBridgeMoonbeam,
            "Moonbeam: wormholeRelayer() should return coreBridge"
        );
        assertEq(
            address(adapter.xERC20()),
            xwellAddrMoonbeam,
            "Moonbeam: xERC20 should be xWELL"
        );
        assertEq(adapter.gasLimit(), 300_000, "Moonbeam: gas limit changed");
    }

    function testMoonbeamReinitializeFails() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrMoonbeam
        );

        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(
            address(1),
            address(1),
            address(0),
            address(0),
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
    }

    function testMoonbeamBridgeInSuccess() public {
        vm.selectFork(MOONBEAM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrMoonbeam,
            adapterAddrMoonbeam,
            startingWellAmount
        );
        uint256 startingBalance = xWELL(xwellAddrMoonbeam).balanceOf(user);

        vm.expectEmit(true, true, true, true, adapterAddrMoonbeam);
        emit BridgedIn(BASE_WORMHOLE_CHAIN_ID, user, mintAmount);

        _bridgeInViaVaa(
            adapterAddrMoonbeam,
            coreBridgeMoonbeam,
            user,
            mintAmount,
            0,
            BASE_WORMHOLE_CHAIN_ID
        );

        assertEq(
            xWELL(xwellAddrMoonbeam).balanceOf(user),
            startingBalance + mintAmount,
            "Moonbeam: user xWELL balance incorrect"
        );
    }

    function testMoonbeamBridgeInReplayFails() public {
        vm.selectFork(MOONBEAM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrMoonbeam,
            adapterAddrMoonbeam,
            startingWellAmount / 2
        );

        _bridgeInViaVaa(
            adapterAddrMoonbeam,
            coreBridgeMoonbeam,
            user,
            mintAmount,
            0,
            BASE_WORMHOLE_CHAIN_ID
        );

        bytes32 emitterAddr = bytes32(uint256(uint160(adapterAddrMoonbeam)));
        bytes memory payload = abi.encode(user, mintAmount);
        _mockParseAndVerifyVM(
            coreBridgeMoonbeam,
            BASE_WORMHOLE_CHAIN_ID,
            emitterAddr,
            0,
            payload
        );

        vm.expectRevert();
        WormholeBridgeAdapter(adapterAddrMoonbeam).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testMoonbeamBridgeInFailsUntrustedSender() public {
        vm.selectFork(MOONBEAM_FORK_ID);

        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(user, startingWellAmount);
        _mockParseAndVerifyVM(
            coreBridgeMoonbeam,
            BASE_WORMHOLE_CHAIN_ID,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        WormholeBridgeAdapter(adapterAddrMoonbeam).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testMoonbeamBridgeOutOffchainQuote() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrMoonbeam
        );

        uint256 mintAmount = _boundMintAmount(
            xwellAddrMoonbeam,
            adapterAddrMoonbeam,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrMoonbeam,
            coreBridgeMoonbeam,
            user,
            mintAmount,
            0,
            BASE_WORMHOLE_CHAIN_ID
        );

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrMoonbeam).balanceOf(user);

        /// Mock the executor so it accepts the off-chain signed quote
        _mockExecutorRequestExecution(executorMoonbeam);

        uint256 messageFee = IWormhole(coreBridgeMoonbeam).messageFee();
        uint256 totalCost = messageFee + 0.01 ether;
        vm.deal(user, totalCost);
        vm.startPrank(user);
        xWELL(xwellAddrMoonbeam).approve(adapterAddrMoonbeam, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrMoonbeam);
        emit TokensSent(BASE_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: totalCost}(
            BASE_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user,
            bytes("mock-signed-quote")
        );
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(
            xWELL(xwellAddrMoonbeam).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Moonbeam: balance incorrect after bridge out"
        );
    }

    function testMoonbeamDeprecatedReceiveReverts() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        WormholeBridgeAdapter(adapterAddrMoonbeam).receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

    /// ========================================================
    /// ===================== Base Tests =======================
    /// ========================================================

    function testBaseSetupAfterUpgrade() public {
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterAddrBase);

        assertEq(
            address(adapter.coreBridge()),
            coreBridgeBase,
            "Base: coreBridge not set"
        );
        assertTrue(
            address(adapter.executor()) != address(0),
            "Base: executor not set"
        );
        assertEq(
            adapter.wormholeChainId(),
            BASE_WORMHOLE_CHAIN_ID,
            "Base: wormholeChainId not set"
        );
        assertEq(
            address(adapter.wormholeRelayer()),
            coreBridgeBase,
            "Base: wormholeRelayer() should return coreBridge"
        );
        assertEq(
            address(adapter.xERC20()),
            xwellAddrBase,
            "Base: xERC20 should be xWELL"
        );
        assertEq(adapter.gasLimit(), 300_000, "Base: gas limit changed");
    }

    function testBaseReinitializeFails() public {
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterAddrBase);

        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(
            address(1),
            address(1),
            address(0),
            address(0),
            BASE_WORMHOLE_CHAIN_ID
        );
    }

    function testBaseBridgeInSuccess() public {
        vm.selectFork(BASE_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrBase,
            adapterAddrBase,
            startingWellAmount
        );
        uint256 startingBalance = xWELL(xwellAddrBase).balanceOf(user);

        vm.expectEmit(true, true, true, true, adapterAddrBase);
        emit BridgedIn(MOONBEAM_WORMHOLE_CHAIN_ID, user, mintAmount);

        _bridgeInViaVaa(
            adapterAddrBase,
            coreBridgeBase,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        assertEq(
            xWELL(xwellAddrBase).balanceOf(user),
            startingBalance + mintAmount,
            "Base: user xWELL balance incorrect"
        );
    }

    function testBaseBridgeInReplayFails() public {
        vm.selectFork(BASE_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrBase,
            adapterAddrBase,
            startingWellAmount / 2
        );

        _bridgeInViaVaa(
            adapterAddrBase,
            coreBridgeBase,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        bytes32 emitterAddr = bytes32(uint256(uint160(adapterAddrBase)));
        bytes memory payload = abi.encode(user, mintAmount);
        _mockParseAndVerifyVM(
            coreBridgeBase,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            emitterAddr,
            0,
            payload
        );

        vm.expectRevert();
        WormholeBridgeAdapter(adapterAddrBase).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testBaseBridgeInFailsUntrustedSender() public {
        vm.selectFork(BASE_FORK_ID);

        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(user, startingWellAmount);
        _mockParseAndVerifyVM(
            coreBridgeBase,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        WormholeBridgeAdapter(adapterAddrBase).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testBaseBridgeOutOnchainQuote() public {
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterAddrBase);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrBase,
            adapterAddrBase,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrBase,
            coreBridgeBase,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 cost = adapter.bridgeCost(MOONBEAM_WORMHOLE_CHAIN_ID);
        if (cost == 0) return; /// quoter not live on fork

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrBase).balanceOf(user);

        vm.deal(user, cost);
        vm.startPrank(user);
        xWELL(xwellAddrBase).approve(adapterAddrBase, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrBase);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: cost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user
        );
        vm.stopPrank();

        assertEq(
            xWELL(xwellAddrBase).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Base: balance incorrect after on-chain bridge out"
        );
    }

    function testBaseBridgeOutOffchainQuote() public {
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(adapterAddrBase);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrBase,
            adapterAddrBase,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrBase,
            coreBridgeBase,
            user,
            mintAmount,
            1,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrBase).balanceOf(user);

        _mockExecutorRequestExecution(executorBase);

        uint256 messageFee = IWormhole(coreBridgeBase).messageFee();
        uint256 totalCost = messageFee + 0.01 ether;
        vm.deal(user, totalCost);
        vm.startPrank(user);
        xWELL(xwellAddrBase).approve(adapterAddrBase, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrBase);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: totalCost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user,
            bytes("mock-signed-quote")
        );
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(
            xWELL(xwellAddrBase).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Base: balance incorrect after off-chain bridge out"
        );
    }

    function testBaseDeprecatedReceiveReverts() public {
        vm.selectFork(BASE_FORK_ID);
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        WormholeBridgeAdapter(adapterAddrBase).receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

    /// ========================================================
    /// ================== Optimism Tests ======================
    /// ========================================================

    function testOptimismSetupAfterUpgrade() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrOptimism
        );

        assertEq(
            address(adapter.coreBridge()),
            coreBridgeOptimism,
            "Optimism: coreBridge not set"
        );
        assertTrue(
            address(adapter.executor()) != address(0),
            "Optimism: executor not set"
        );
        assertEq(
            adapter.wormholeChainId(),
            OPTIMISM_WORMHOLE_CHAIN_ID,
            "Optimism: wormholeChainId not set"
        );
        assertEq(
            address(adapter.wormholeRelayer()),
            coreBridgeOptimism,
            "Optimism: wormholeRelayer() should return coreBridge"
        );
        assertEq(
            address(adapter.xERC20()),
            xwellAddrOptimism,
            "Optimism: xERC20 should be xWELL"
        );
        assertEq(adapter.gasLimit(), 300_000, "Optimism: gas limit changed");
    }

    function testOptimismReinitializeFails() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrOptimism
        );

        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(
            address(1),
            address(1),
            address(0),
            address(0),
            OPTIMISM_WORMHOLE_CHAIN_ID
        );
    }

    function testOptimismBridgeInSuccess() public {
        vm.selectFork(OPTIMISM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrOptimism,
            adapterAddrOptimism,
            startingWellAmount
        );
        uint256 startingBalance = xWELL(xwellAddrOptimism).balanceOf(user);

        vm.expectEmit(true, true, true, true, adapterAddrOptimism);
        emit BridgedIn(MOONBEAM_WORMHOLE_CHAIN_ID, user, mintAmount);

        _bridgeInViaVaa(
            adapterAddrOptimism,
            coreBridgeOptimism,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        assertEq(
            xWELL(xwellAddrOptimism).balanceOf(user),
            startingBalance + mintAmount,
            "Optimism: user xWELL balance incorrect"
        );
    }

    function testOptimismBridgeInReplayFails() public {
        vm.selectFork(OPTIMISM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrOptimism,
            adapterAddrOptimism,
            startingWellAmount / 2
        );

        _bridgeInViaVaa(
            adapterAddrOptimism,
            coreBridgeOptimism,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        bytes32 emitterAddr = bytes32(uint256(uint160(adapterAddrOptimism)));
        bytes memory payload = abi.encode(user, mintAmount);
        _mockParseAndVerifyVM(
            coreBridgeOptimism,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            emitterAddr,
            0,
            payload
        );

        vm.expectRevert();
        WormholeBridgeAdapter(adapterAddrOptimism).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testOptimismBridgeInFailsUntrustedSender() public {
        vm.selectFork(OPTIMISM_FORK_ID);

        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(user, startingWellAmount);
        _mockParseAndVerifyVM(
            coreBridgeOptimism,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        WormholeBridgeAdapter(adapterAddrOptimism).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testOptimismBridgeOutOnchainQuote() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrOptimism
        );

        uint256 mintAmount = _boundMintAmount(
            xwellAddrOptimism,
            adapterAddrOptimism,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrOptimism,
            coreBridgeOptimism,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 cost = adapter.bridgeCost(MOONBEAM_WORMHOLE_CHAIN_ID);
        if (cost == 0) return; /// quoter not live on fork

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrOptimism).balanceOf(user);

        vm.deal(user, cost);
        vm.startPrank(user);
        xWELL(xwellAddrOptimism).approve(adapterAddrOptimism, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrOptimism);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: cost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user
        );
        vm.stopPrank();

        assertEq(
            xWELL(xwellAddrOptimism).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Optimism: balance incorrect after on-chain bridge out"
        );
    }

    function testOptimismBridgeOutOffchainQuote() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrOptimism
        );

        uint256 mintAmount = _boundMintAmount(
            xwellAddrOptimism,
            adapterAddrOptimism,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrOptimism,
            coreBridgeOptimism,
            user,
            mintAmount,
            1,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrOptimism).balanceOf(user);

        _mockExecutorRequestExecution(executorOptimism);

        uint256 messageFee = IWormhole(coreBridgeOptimism).messageFee();
        uint256 totalCost = messageFee + 0.01 ether;
        vm.deal(user, totalCost);
        vm.startPrank(user);
        xWELL(xwellAddrOptimism).approve(adapterAddrOptimism, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrOptimism);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: totalCost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user,
            bytes("mock-signed-quote")
        );
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(
            xWELL(xwellAddrOptimism).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Optimism: balance incorrect after off-chain bridge out"
        );
    }

    function testOptimismDeprecatedReceiveReverts() public {
        vm.selectFork(OPTIMISM_FORK_ID);
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        WormholeBridgeAdapter(adapterAddrOptimism).receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

    /// ========================================================
    /// ================== Ethereum Tests ======================
    /// ========================================================

    function testEthereumSetupAfterUpgrade() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrEthereum
        );

        assertEq(
            address(adapter.coreBridge()),
            addresses.getAddress("WORMHOLE_CORE"),
            "Ethereum: coreBridge not set"
        );
        assertEq(
            address(adapter.executor()),
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            "Ethereum: executor not set"
        );
        assertEq(
            adapter.wormholeChainId(),
            ETHEREUM_WORMHOLE_CHAIN_ID,
            "Ethereum: wormholeChainId not set"
        );
        assertEq(
            address(adapter.wormholeRelayer()),
            addresses.getAddress("WORMHOLE_CORE"),
            "Ethereum: wormholeRelayer() should return coreBridge"
        );
        assertEq(
            address(adapter.xERC20()),
            xwellAddrEthereum,
            "Ethereum: xERC20 should be xWELL"
        );
        assertEq(adapter.gasLimit(), 300_000, "Ethereum: gas limit changed");
    }

    function testEthereumReinitializeFails() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrEthereum
        );

        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(
            address(1),
            address(1),
            address(0),
            address(0),
            ETHEREUM_WORMHOLE_CHAIN_ID
        );
    }

    function testEthereumBridgeInSuccess() public {
        vm.selectFork(ETHEREUM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrEthereum,
            adapterAddrEthereum,
            startingWellAmount
        );
        uint256 startingBalance = xWELL(xwellAddrEthereum).balanceOf(user);

        vm.expectEmit(true, true, true, true, adapterAddrEthereum);
        emit BridgedIn(MOONBEAM_WORMHOLE_CHAIN_ID, user, mintAmount);

        _bridgeInViaVaa(
            adapterAddrEthereum,
            coreBridgeEthereum,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        assertEq(
            xWELL(xwellAddrEthereum).balanceOf(user),
            startingBalance + mintAmount,
            "Ethereum: user xWELL balance incorrect"
        );
    }

    function testEthereumBridgeInReplayFails() public {
        vm.selectFork(ETHEREUM_FORK_ID);

        uint256 mintAmount = _boundMintAmount(
            xwellAddrEthereum,
            adapterAddrEthereum,
            startingWellAmount / 2
        );

        _bridgeInViaVaa(
            adapterAddrEthereum,
            coreBridgeEthereum,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        bytes32 emitterAddr = bytes32(uint256(uint160(adapterAddrEthereum)));
        bytes memory payload = abi.encode(user, mintAmount);
        _mockParseAndVerifyVM(
            coreBridgeEthereum,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            emitterAddr,
            0,
            payload
        );

        vm.expectRevert();
        WormholeBridgeAdapter(adapterAddrEthereum).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testEthereumBridgeInFailsUntrustedSender() public {
        vm.selectFork(ETHEREUM_FORK_ID);

        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(user, startingWellAmount);
        _mockParseAndVerifyVM(
            coreBridgeEthereum,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        WormholeBridgeAdapter(adapterAddrEthereum).executeVAAv1(
            abi.encode(uint64(0))
        );
        vm.clearMockedCalls();
    }

    function testEthereumBridgeOutOnchainQuote() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrEthereum
        );

        uint256 mintAmount = _boundMintAmount(
            xwellAddrEthereum,
            adapterAddrEthereum,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrEthereum,
            coreBridgeEthereum,
            user,
            mintAmount,
            0,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 cost = adapter.bridgeCost(MOONBEAM_WORMHOLE_CHAIN_ID);
        if (cost == 0) return; /// quoter not live on fork

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrEthereum).balanceOf(user);

        vm.deal(user, cost);
        vm.startPrank(user);
        xWELL(xwellAddrEthereum).approve(adapterAddrEthereum, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrEthereum);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: cost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user
        );
        vm.stopPrank();

        assertEq(
            xWELL(xwellAddrEthereum).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Ethereum: balance incorrect after on-chain bridge out"
        );
    }

    function testEthereumBridgeOutOffchainQuote() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            adapterAddrEthereum
        );

        uint256 mintAmount = _boundMintAmount(
            xwellAddrEthereum,
            adapterAddrEthereum,
            startingWellAmount
        );
        _bridgeInViaVaa(
            adapterAddrEthereum,
            coreBridgeEthereum,
            user,
            mintAmount,
            1,
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        uint256 bridgeOutAmount = mintAmount / 2;
        uint256 startingBalance = xWELL(xwellAddrEthereum).balanceOf(user);

        _mockExecutorRequestExecution(executorEthereum);

        uint256 messageFee = IWormhole(coreBridgeEthereum).messageFee();
        uint256 totalCost = messageFee + 0.01 ether;
        vm.deal(user, totalCost);
        vm.startPrank(user);
        xWELL(xwellAddrEthereum).approve(adapterAddrEthereum, bridgeOutAmount);

        vm.expectEmit(true, true, true, true, adapterAddrEthereum);
        emit TokensSent(MOONBEAM_WORMHOLE_CHAIN_ID, user, bridgeOutAmount);

        adapter.bridge{value: totalCost}(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            bridgeOutAmount,
            user,
            bytes("mock-signed-quote")
        );
        vm.stopPrank();
        vm.clearMockedCalls();

        assertEq(
            xWELL(xwellAddrEthereum).balanceOf(user),
            startingBalance - bridgeOutAmount,
            "Ethereum: balance incorrect after off-chain bridge out"
        );
    }

    function testEthereumDeprecatedReceiveReverts() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        WormholeBridgeAdapter(adapterAddrEthereum).receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

    /// ========================================================
    /// ============= Cross-Chain Consistency Tests ============
    /// ========================================================

    function testAllChainsV3Initialized() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        assertEq(
            WormholeBridgeAdapter(adapterAddrMoonbeam).wormholeChainId(),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            "Moonbeam V3 not initialized"
        );

        vm.selectFork(BASE_FORK_ID);
        assertEq(
            WormholeBridgeAdapter(adapterAddrBase).wormholeChainId(),
            BASE_WORMHOLE_CHAIN_ID,
            "Base V3 not initialized"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        assertEq(
            WormholeBridgeAdapter(adapterAddrOptimism).wormholeChainId(),
            OPTIMISM_WORMHOLE_CHAIN_ID,
            "Optimism V3 not initialized"
        );

        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            WormholeBridgeAdapter(adapterAddrEthereum).wormholeChainId(),
            ETHEREUM_WORMHOLE_CHAIN_ID,
            "Ethereum V3 not initialized"
        );
    }

    function testAllChainsBridgeCostDoesNotRevert() public view {
        /// bridgeCost uses try/catch so it should never revert,
        /// even if the executor quoter is not live on the fork.
        WormholeBridgeAdapter(adapterAddrMoonbeam).bridgeCost(
            BASE_WORMHOLE_CHAIN_ID
        );
        WormholeBridgeAdapter(adapterAddrBase).bridgeCost(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        WormholeBridgeAdapter(adapterAddrOptimism).bridgeCost(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        WormholeBridgeAdapter(adapterAddrEthereum).bridgeCost(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
    }

    function testBridgeInFailsWithValueAllChains() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        vm.deal(address(this), 1 ether);
        vm.expectRevert("WormholeBridge: no value allowed");
        WormholeBridgeAdapter(adapterAddrMoonbeam).executeVAAv1{value: 1}(
            bytes("")
        );

        vm.selectFork(BASE_FORK_ID);
        vm.deal(address(this), 1 ether);
        vm.expectRevert("WormholeBridge: no value allowed");
        WormholeBridgeAdapter(adapterAddrBase).executeVAAv1{value: 1}(
            bytes("")
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        vm.deal(address(this), 1 ether);
        vm.expectRevert("WormholeBridge: no value allowed");
        WormholeBridgeAdapter(adapterAddrOptimism).executeVAAv1{value: 1}(
            bytes("")
        );

        vm.selectFork(ETHEREUM_FORK_ID);
        vm.deal(address(this), 1 ether);
        vm.expectRevert("WormholeBridge: no value allowed");
        WormholeBridgeAdapter(adapterAddrEthereum).executeVAAv1{value: 1}(
            bytes("")
        );
    }

    function testBridgeOutFailsInvalidTargetAllChains() public {
        uint16 invalidChainId = 999;

        vm.selectFork(MOONBEAM_FORK_ID);
        vm.expectRevert("WormholeBridge: invalid target chain");
        WormholeBridgeAdapter(adapterAddrMoonbeam).bridge{value: 0}(
            invalidChainId,
            1e18,
            user,
            bytes("")
        );

        vm.selectFork(BASE_FORK_ID);
        vm.expectRevert("WormholeBridge: invalid target chain");
        WormholeBridgeAdapter(adapterAddrBase).bridge{value: 0}(
            invalidChainId,
            1e18,
            user,
            bytes("")
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        vm.expectRevert("WormholeBridge: invalid target chain");
        WormholeBridgeAdapter(adapterAddrOptimism).bridge{value: 0}(
            invalidChainId,
            1e18,
            user,
            bytes("")
        );

        vm.selectFork(ETHEREUM_FORK_ID);
        vm.expectRevert("WormholeBridge: invalid target chain");
        WormholeBridgeAdapter(adapterAddrEthereum).bridge{value: 0}(
            invalidChainId,
            1e18,
            user,
            bytes("")
        );
    }
}

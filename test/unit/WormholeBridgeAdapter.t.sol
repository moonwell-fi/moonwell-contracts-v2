pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MockCoreBridgeForAdapter} from "@test/mock/MockCoreBridgeForAdapter.sol";
import {MockExecutorQuoterRouter} from "@test/mock/MockExecutorQuoterRouter.sol";

contract WormholeBridgeAdapterUnitTest is BaseTest {
    /// xerc20 bridge adapter events

    /// @notice emitted when tokens are bridged out
    event BridgedOut(
        uint256 indexed dstChainId,
        address indexed bridgeUser,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// @notice emitted when tokens are bridged in
    event BridgedIn(
        uint256 indexed srcChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// wormhole events
    event TokensSent(
        uint16 indexed dstChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    event TargetAddressUpdated(
        uint16 indexed dstChainId,
        address indexed target
    );

    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// state variables
    address to;
    uint256 amount;

    function setUp() public override {
        super.setUp();
        to = address(999999999999999);
        amount = 100 * 1e18;
    }

    /// --------------------------------------------------------
    /// ------------------- Helper Functions -------------------
    /// --------------------------------------------------------

    function _setupVaa(
        uint16 emitterChainId,
        bytes32 emitterAddress,
        uint64 sequence,
        bytes memory payload
    ) internal returns (bytes memory encodedVaa) {
        mockCoreBridge.setVmData(
            emitterChainId,
            emitterAddress,
            sequence,
            payload
        );
        encodedVaa = abi.encode(
            "mock-vaa",
            emitterChainId,
            emitterAddress,
            sequence
        );
    }

    function _bridgeInViaVaa(uint64 sequence) internal {
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(
            chainId,
            emitterAddr,
            sequence,
            payload
        );

        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// -------------------- Setup Tests -----------------------
    /// --------------------------------------------------------

    function testSetup() public view {
        assertEq(wormholeBridgeAdapterProxy.owner(), owner, "invalid owner");
        assertEq(
            address(wormholeBridgeAdapterProxy.wormhole()),
            address(mockCoreBridge),
            "invalid wormhole core bridge"
        );
        assertEq(
            address(wormholeBridgeAdapterProxy.executorQuoterRouter()),
            address(mockExecutorQuoterRouter),
            "invalid executor quoter router"
        );
        assertTrue(
            wormholeBridgeAdapterProxy.isTrustedSender(
                chainId,
                address(wormholeBridgeAdapterProxy)
            ),
            "trusted sender not set"
        );
        assertEq(
            wormholeBridgeAdapterProxy.targetAddress(chainId),
            address(wormholeBridgeAdapterProxy),
            "target address not set"
        );
        assertEq(
            address(xwellProxy),
            address(wormholeBridgeAdapterProxy.xERC20()),
            "incorrect xerc20 in bridge adapter"
        );
    }

    function testAllTrustedSendersTrusted() public view {
        bytes32[] memory trustedSenders = wormholeBridgeAdapterProxy
            .allTrustedSenders(chainId);

        for (uint256 i = 0; i < trustedSenders.length; i++) {
            assertTrue(
                wormholeBridgeAdapterProxy.isTrustedSender(
                    chainId,
                    trustedSenders[i]
                ),
                "trusted sender not trusted"
            );
        }
    }

    function testInitializingFails() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wormholeBridgeAdapterProxy.initialize(
            address(xwellProxy),
            owner,
            address(wormholeBridgeAdapterProxy),
            new uint16[](0),
            new address[](0)
        );
    }

    function testInitializeV5FailsAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wormholeBridgeAdapterProxy.initializeV5(
            address(mockExecutorQuoterRouter),
            address(mockExecutorQuoterRouter),
            address(0)
        );
    }

    function testInitializeV5FailsZeroExecutor() public {
        /// deploy a fresh proxy so initializeV5 hasn't been called yet
        ProxyAdmin freshAdmin = new ProxyAdmin();
        WormholeBridgeAdapter freshProxy = WormholeBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(wormholeBridgeAdapter),
                    address(freshAdmin),
                    ""
                )
            )
        );

        /// initialize V3 first to set wormhole
        freshProxy.initializeV3(address(mockCoreBridge));

        vm.expectRevert("WormholeBridge: zero address");
        freshProxy.initializeV5(address(0), address(1), address(1));
    }

    function testInitializeV5FailsZeroQuoterRouter() public {
        ProxyAdmin freshAdmin = new ProxyAdmin();
        WormholeBridgeAdapter freshProxy = WormholeBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(wormholeBridgeAdapter),
                    address(freshAdmin),
                    ""
                )
            )
        );

        freshProxy.initializeV3(address(mockCoreBridge));

        vm.expectRevert("WormholeBridge: zero quoter address");
        freshProxy.initializeV5(address(1), address(0), address(1));
    }

    function testInitializeV5FailsZeroQuoterAddr() public {
        ProxyAdmin freshAdmin = new ProxyAdmin();
        WormholeBridgeAdapter freshProxy = WormholeBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(wormholeBridgeAdapter),
                    address(freshAdmin),
                    ""
                )
            )
        );

        freshProxy.initializeV3(address(mockCoreBridge));

        vm.expectRevert("WormholeBridge: zero quoter address");
        freshProxy.initializeV5(address(1), address(1), address(0));
    }

    function testInitializeV5MoonbeamAllowsZeroQuoter() public {
        /// Moonbeam (wormhole chain ID 16) has no on-chain quoter
        MockCoreBridgeForAdapter moonbeamBridge = new MockCoreBridgeForAdapter();
        moonbeamBridge.setChainId(16);

        ProxyAdmin freshAdmin = new ProxyAdmin();
        WormholeBridgeAdapter freshProxy = WormholeBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(wormholeBridgeAdapter),
                    address(freshAdmin),
                    ""
                )
            )
        );

        freshProxy.initializeV3(address(moonbeamBridge));
        freshProxy.initializeV5(address(1), address(0), address(0));

        assertEq(
            address(freshProxy.executor()),
            address(1),
            "executor should be set"
        );
    }

    function testInitializeV5FailsWormholeNotSet() public {
        /// deploy a fresh proxy without calling initializeV3
        ProxyAdmin freshAdmin = new ProxyAdmin();
        WormholeBridgeAdapter freshProxy = WormholeBridgeAdapter(
            address(
                new TransparentUpgradeableProxy(
                    address(wormholeBridgeAdapter),
                    address(freshAdmin),
                    ""
                )
            )
        );

        vm.expectRevert("WormholeBridge: zero address");
        freshProxy.initializeV5(address(1), address(1), address(1));
    }

    /// --------------------------------------------------------
    /// ------------------- ACL Failure Tests ------------------
    /// --------------------------------------------------------

    function testSetGasLimitNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wormholeBridgeAdapterProxy.setGasLimit(1);
    }

    function testRemoveTrustedSendersNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wormholeBridgeAdapterProxy.removeTrustedSenders(
            new WormholeTrustedSender.TrustedSender[](0)
        );
    }

    function testAddTrustedSendersNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wormholeBridgeAdapterProxy.addTrustedSenders(
            new WormholeTrustedSender.TrustedSender[](0)
        );
    }

    function testSetTargetAddressesNonOwnerFails() public {
        vm.expectRevert("Ownable: caller is not the owner");
        wormholeBridgeAdapterProxy.setTargetAddresses(
            new WormholeTrustedSender.TrustedSender[](0)
        );
    }

    /// --------------------------------------------------------
    /// ------------------- ACL Success Tests ------------------
    /// --------------------------------------------------------

    function testSetGasLimitOwnerSucceeds(uint96 newGasLimit) public {
        uint96 oldGasLimit = wormholeBridgeAdapterProxy.gasLimit();
        vm.prank(owner);
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit GasLimitUpdated(oldGasLimit, newGasLimit);
        wormholeBridgeAdapterProxy.setGasLimit(newGasLimit);

        assertEq(wormholeBridgeAdapterProxy.gasLimit(), newGasLimit);
    }

    function testRemoveTrustedSendersOwnerSucceeds() public {
        testAddTrustedSendersOwnerSucceeds(address(this));

        WormholeTrustedSender.TrustedSender[]
            memory sender = new WormholeTrustedSender.TrustedSender[](1);
        sender[0].addr = address(this);
        sender[0].chainId = chainId;

        vm.prank(owner);
        wormholeBridgeAdapterProxy.removeTrustedSenders(sender);

        assertFalse(
            wormholeBridgeAdapterProxy.isTrustedSender(chainId, address(this))
        );
    }

    function testRemoveNonTrustedSendersOwnerFails() public {
        testRemoveTrustedSendersOwnerSucceeds();

        WormholeTrustedSender.TrustedSender[]
            memory sender = new WormholeTrustedSender.TrustedSender[](1);
        sender[0].addr = address(this);
        sender[0].chainId = chainId;

        vm.prank(owner);
        vm.expectRevert("WormholeTrustedSender: not in list");
        wormholeBridgeAdapterProxy.removeTrustedSenders(sender);
    }

    function testAddTrustedSendersOwnerSucceeds(address trustedSender) public {
        vm.assume(trustedSender != address(wormholeBridgeAdapterProxy));
        WormholeTrustedSender.TrustedSender[]
            memory sender = new WormholeTrustedSender.TrustedSender[](1);
        sender[0].addr = trustedSender;
        sender[0].chainId = chainId;

        vm.prank(owner);
        wormholeBridgeAdapterProxy.addTrustedSenders(sender);

        assertTrue(
            wormholeBridgeAdapterProxy.isTrustedSender(chainId, trustedSender)
        );
    }

    function testAddTrustedSendersOwnerFailsAlreadyWhitelisted(
        address trustedSender
    ) public {
        if (trustedSender != address(wormholeBridgeAdapterProxy)) {
            testAddTrustedSendersOwnerSucceeds(trustedSender);
        }

        WormholeTrustedSender.TrustedSender[]
            memory sender = new WormholeTrustedSender.TrustedSender[](1);
        sender[0].addr = trustedSender;
        sender[0].chainId = chainId;

        vm.prank(owner);
        vm.expectRevert("WormholeTrustedSender: already in list");
        wormholeBridgeAdapterProxy.addTrustedSenders(sender);
    }

    function testSetTargetAddressesOwnerSucceeds(
        address addr,
        uint16 newChainId
    ) public {
        WormholeTrustedSender.TrustedSender[]
            memory sender = new WormholeTrustedSender.TrustedSender[](1);
        sender[0].addr = addr;
        sender[0].chainId = newChainId;

        vm.prank(owner);
        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit TargetAddressUpdated(newChainId, addr);
        wormholeBridgeAdapterProxy.setTargetAddresses(sender);

        assertEq(wormholeBridgeAdapterProxy.targetAddress(newChainId), addr);
    }

    /// --------------------------------------------------------
    /// --------------- Initialization Tests -------------------
    /// --------------------------------------------------------

    function testInitializeFailsArrayLengthMismatch() public {
        ProxyAdmin admin = new ProxyAdmin();
        (, , , , address wormholeAdapterProxy, ) = deployMoonbeamSystem(
            address(well),
            address(admin)
        );
        wormholeBridgeAdapterProxy = WormholeBridgeAdapter(
            wormholeAdapterProxy
        );

        vm.expectRevert("WormholeBridge: array length mismatch");
        wormholeBridgeAdapterProxy.initialize(
            address(xwellProxy),
            owner,
            address(wormholeBridgeAdapterProxy),
            new uint16[](1),
            new address[](0)
        );
    }

    /// --------------------------------------------------------
    /// ----------- executeVAAv1 Failure Tests -----------------
    /// --------------------------------------------------------

    function testExecuteVAAv1FailsWithValue() public {
        vm.deal(address(this), 100);
        vm.expectRevert("WormholeBridge: no value allowed");
        wormholeBridgeAdapterProxy.executeVAAv1{value: 100}(bytes("fake-vaa"));
    }

    function testExecuteVAAv1FailsInvalidVaa() public {
        mockCoreBridge.setValid(false, "bad signature");
        vm.expectRevert("bad signature");
        wormholeBridgeAdapterProxy.executeVAAv1(bytes("invalid-vaa"));
    }

    function testExecuteVAAv1FailsUntrustedSender() public {
        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(
            chainId,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    function testExecuteVAAv1FailsReplay() public {
        _bridgeInViaVaa(0);

        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 0, payload);

        vm.expectRevert();
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// ----------- executeVAAv1 Success Tests -----------------
    /// --------------------------------------------------------

    function testExecuteVAAv1Succeeds() public {
        uint256 startingBalance = xwellProxy.balanceOf(to);
        uint256 startingTotalSupply = xwellProxy.totalSupply();

        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 0, payload);

        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit BridgedIn(chainId, to, amount);
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);

        assertEq(xwellProxy.balanceOf(to) - startingBalance, amount);
        assertEq(xwellProxy.totalSupply() - startingTotalSupply, amount);
    }

    function testExecuteVAAv1SucceedsMultipleSequences() public {
        uint256 startingBalance = xwellProxy.balanceOf(to);

        _bridgeInViaVaa(0);
        _bridgeInViaVaa(1);
        _bridgeInViaVaa(2);

        assertEq(xwellProxy.balanceOf(to) - startingBalance, amount * 3);
    }

    function testBridgeInFailsRateLimitExhausted() public {
        amount = xwellProxy.buffer(address(wormholeBridgeAdapterProxy));
        _bridgeInViaVaa(0);

        amount = 1;
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 1, payload);

        vm.expectRevert("RateLimited: rate limit hit");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// ---------- Deprecated receiveWormholeMessages ----------
    /// --------------------------------------------------------

    function testReceiveWormholeMessagesAlwaysReverts() public {
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        wormholeBridgeAdapterProxy.receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

    /// --------------------------------------------------------
    /// ------- Target Chain / Address Validation Tests --------
    /// --------------------------------------------------------

    function testExecuteVAAv1RevertsWrongTargetChain() public {
        uint16 wrongChainId = chainId + 1;
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, wrongChainId);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 0, payload);

        vm.expectRevert("WormholeBridge: invalid target chain");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    function testExecuteVAAv1RevertsAlreadyProcessedHash() public {
        /// Simulate a VAA already processed via old processVAA path
        /// by setting processedVAAHashes[hash] = true via vm.store
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount, chainId);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 0, payload);

        /// Compute the hash that MockCoreBridgeForAdapter will return
        bytes32 vaaHash = keccak256(encodedVaa);

        /// processedVAAHashes is a mapping(bytes32 => bool) at storage slot after wormhole (slot 156)
        /// mapping slot = keccak256(abi.encode(key, slot))
        /// wormhole is at slot 156, processedVAAHashes is at slot 157
        bytes32 mappingSlot = keccak256(abi.encode(vaaHash, uint256(157)));
        vm.store(
            address(wormholeBridgeAdapterProxy),
            mappingSlot,
            bytes32(uint256(1))
        );

        vm.expectRevert("WormholeBridge: VAA already processed");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// ------------------- Bridge Out Tests -------------------
    /// --------------------------------------------------------

    function testBridgeOutFailsIncorrectCost() public {
        mockExecutorQuoterRouter.setQuote(0.001 ether);
        mockCoreBridge.setMessageFee(0.0001 ether);

        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        vm.deal(address(this), cost + 1);

        vm.expectRevert("WormholeBridge: cost not equal to quote");
        wormholeBridgeAdapterProxy.bridge{value: cost + 1}(chainId, amount, to);
    }

    function testBridgeOutFailsIncorrectTargetChain() public {
        vm.expectRevert("WormholeBridge: invalid target chain");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId + 1, amount, to);
    }

    function testBridgeOutFailsNoApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    function testBridgeOutFailsNotEnoughBalance() public {
        deal(address(xwellProxy), address(this), amount - 1);
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    function testBridgeOutFailsNotEnoughBuffer() public {
        amount = externalChainBufferCap / 2;
        to = address(this);
        _bridgeInViaVaa(0);

        amount = externalChainBufferCap;
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("RateLimited: buffer cap overflow");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount + 1, to);
    }

    function testBridgeOutSucceeds() public {
        amount = externalChainBufferCap / 2;
        to = address(this);
        _bridgeInViaVaa(0);

        amount = externalChainBufferCap;
        _lockboxCanMintTo(address(this), uint112(amount));
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit TokensSent(chainId, to, amount);
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// --------------------------------------------------------
    /// ------------------- Bridge Cost Tests ------------------
    /// --------------------------------------------------------

    function testBridgeCostReturnsQuotePlusMessageFee() public {
        mockExecutorQuoterRouter.setQuote(0.01 ether);
        mockCoreBridge.setMessageFee(0.001 ether);

        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        assertEq(cost, 0.011 ether);
    }

    function testBridgeCostReturnsZeroWhenQuoteFails() public {
        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId + 1);
        assertEq(cost, 0);
    }

    function testBridgeCostReturnsZeroWhenNoQuoterRouter() public {
        /// Deploy a fresh adapter without executorQuoterRouter
        ProxyAdmin admin = new ProxyAdmin();
        (, , , , address freshAdapterProxy, ) = deployMoonbeamSystem(
            address(well),
            address(admin)
        );
        WormholeBridgeAdapter freshAdapter = WormholeBridgeAdapter(
            freshAdapterProxy
        );

        /// Only V3 (wormhole), no V4 (executor) — simulates Moonbeam-like scenario
        freshAdapter.initializeV3(address(mockCoreBridge));

        uint256 cost = freshAdapter.bridgeCost(chainId);
        assertEq(cost, 0, "should return 0 when no executorQuoterRouter");
    }

    /// --------------------------------------------------------
    /// ----------- Off-Chain Quote Bridge Out Tests ------------
    /// --------------------------------------------------------

    function testBridgeOutWithSignedQuoteSucceeds() public {
        amount = externalChainBufferCap / 2;
        to = address(this);
        _bridgeInViaVaa(0);

        amount = externalChainBufferCap;
        _lockboxCanMintTo(address(this), uint112(amount));
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        /// off-chain quote path: msg.value covers messageFee + executor fee
        bytes memory signedQuote = hex"deadbeef";
        uint256 messageFee = mockCoreBridge.mockMessageFee();
        uint256 executorFee = 0.001 ether;
        vm.deal(address(this), messageFee + executorFee);

        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit TokensSent(chainId, to, amount);
        wormholeBridgeAdapterProxy.bridge{value: messageFee + executorFee}(
            chainId,
            amount,
            to,
            signedQuote
        );

        /// executor mock should have received the fee
        assertEq(mockExecutorQuoterRouter.requestCount(), 1);
        assertEq(mockExecutorQuoterRouter.lastDstChain(), chainId);
    }

    function testBridgeOutWithSignedQuoteFailsInvalidTargetChain() public {
        bytes memory signedQuote = hex"deadbeef";
        vm.expectRevert("WormholeBridge: invalid target chain");
        wormholeBridgeAdapterProxy.bridge{value: 0}(
            chainId + 1,
            amount,
            to,
            signedQuote
        );
    }

    function testBridgeOutWithSignedQuoteFailsNoApproval() public {
        bytes memory signedQuote = hex"deadbeef";
        vm.expectRevert("ERC20: insufficient allowance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(
            chainId,
            amount,
            to,
            signedQuote
        );
    }
}

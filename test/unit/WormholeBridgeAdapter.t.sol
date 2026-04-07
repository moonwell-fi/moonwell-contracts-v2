pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {Address} from "@utils/Address.sol";
import {MockWormholeReceiver} from "@test/mock/MockWormholeReceiver.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

contract WormholeBridgeAdapterUnitTest is BaseTest {
    using Address for address;

    /// xerc20 bridge adapter events

    /// @notice emitted when tokens are bridged out
    /// @param dstChainId destination chain id to send tokens to
    /// @param bridgeUser user who bridged out tokens
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged out
    event BridgedOut(
        uint256 indexed dstChainId,
        address indexed bridgeUser,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// @notice emitted when tokens are bridged in
    /// @param srcChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event BridgedIn(
        uint256 indexed srcChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// wormhole events

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId source chain id tokens were bridged from
    /// @param tokenReceiver address to receive tokens on destination chain
    /// @param amount of tokens bridged in
    event TokensSent(
        uint16 indexed dstChainId,
        address indexed tokenReceiver,
        uint256 amount
    );

    /// @notice chain id of the target chain to address for bridging
    /// @param dstChainId destination chain id to send tokens to
    /// @param target address to send tokens to
    event TargetAddressUpdated(
        uint16 indexed dstChainId,
        address indexed target
    );

    /// @notice emitted when the gas limit changes on external chains
    /// @param oldGasLimit old gas limit
    /// @param newGasLimit new gas limit
    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// state variables

    /// @notice address to send tokens to
    address to;

    /// @notice amount of tokens to mint
    uint256 amount;

    /// relayer gas cost
    uint256 public constant gasCost = 0.00001 * 1 ether;

    /// mock wormhole receiver
    MockWormholeReceiver receiver;

    function setUp() public override {
        super.setUp();
        to = address(999999999999999);
        amount = 100 * 1e18;
        receiver = new MockWormholeReceiver();
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(sload(receiver.slot))
        }

        bytes memory runtimeBytecode = new bytes(codeSize);

        assembly {
            extcodecopy(
                sload(receiver.slot),
                add(runtimeBytecode, 0x20),
                0,
                codeSize
            )
        }

        /// set the wormhole relayer address to have the
        /// runtime bytecode of the mock wormhole relayer
        vm.etch(wormholeRelayer, runtimeBytecode);
    }

    function testSetup() public view {
        assertEq(wormholeBridgeAdapterProxy.owner(), owner, "invalid owner");
        assertEq(
            address(wormholeBridgeAdapterProxy.wormholeRelayer()),
            wormholeRelayer,
            "invalid wormhole relayer"
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
        assertEq(
            xwellProxy.buffer(address(wormholeBridgeAdapterProxy)),
            externalChainBufferCap / 2,
            "incorrect buffer for wormhole bridge adapter"
        );
        assertEq(
            xwellProxy.bufferCap(address(wormholeBridgeAdapterProxy)),
            externalChainBufferCap,
            "incorrect buffer cap for wormhole bridge adapter"
        );
        assertEq(
            MockWormholeReceiver(wormholeRelayer).price(),
            0,
            "price not zero"
        );
        assertEq(
            MockWormholeReceiver(wormholeRelayer).nonce(),
            0,
            "nonce not zero"
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

    /// ACL failure tests

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

    /// ACL success tests

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

        assertEq(
            wormholeBridgeAdapterProxy.gasLimit(),
            newGasLimit,
            "incorrect new gas limit"
        );
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
            wormholeBridgeAdapterProxy.isTrustedSender(chainId, address(this)),
            "trusted sender not un-set"
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
            wormholeBridgeAdapterProxy.isTrustedSender(chainId, trustedSender),
            "trusted sender not set"
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

        assertEq(
            wormholeBridgeAdapterProxy.targetAddress(newChainId),
            addr,
            "target address not set correctly"
        );
    }

    /// initialization
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

    /// receiveWormholeMessages is deprecated and should revert after V3 upgrade
    function testReceiveWormholeMessagesRevertsAfterV3() public {
        _upgradeToV3();

        vm.prank(wormholeRelayer);
        vm.expectRevert("WormholeBridgeAdapter: relayer disabled");
        wormholeBridgeAdapterProxy.receiveWormholeMessages{value: 0}(
            abi.encode(to, amount),
            new bytes[](0),
            address(wormholeBridgeAdapterProxy).toBytes(),
            chainId,
            bytes32(uint256(77777))
        );
    }

    /// bridge out tests:
    /// NOTE: bridge out now requires V3 upgrade (wormhole must be set)

    /// incorrect cost
    function testBridgeOutFailsIncorrectCost() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        vm.deal(address(this), 1);
        vm.expectRevert("WormholeBridgeAdapter: cost not equal to quote");
        wormholeBridgeAdapterProxy.bridge{value: 1}(chainId, amount, to);
    }

    /// incorrect target chain
    function testBridgeOutFailsIncorrectTargetChain() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        vm.expectRevert("WormholeBridgeAdapter: invalid target chain");
        wormholeBridgeAdapterProxy.bridge{value: 0}(
            chainId + 1, /// invalid chain id
            amount,
            to
        );
    }

    /// not enough approvals
    function testBridgeOutFailsNoApproval() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        vm.expectRevert("ERC20: insufficient allowance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// not enough balance
    function testBridgeOutFailsNotEnoughBalance() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        deal(address(xwellProxy), address(this), amount - 1);
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// not enough rate limit
    function testBridgeOutFailsNotEnoughBuffer() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        amount = externalChainBufferCap / 2;
        to = address(this);

        _mintViaProcessVAA(mockWormhole, to, amount, hex"aa01");

        amount = externalChainBufferCap;
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("RateLimited: buffer cap overflow");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount + 1, to);
    }

    function testBridgeOutSucceeds() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        amount = externalChainBufferCap / 2;
        to = address(this);

        _mintViaProcessVAA(mockWormhole, to, amount, hex"aa02");

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

    /// ---------------------------------------------------------
    /// ---------------------------------------------------------
    /// -------------- V3 / processVAA Tests --------------------
    /// ---------------------------------------------------------
    /// ---------------------------------------------------------

    /// @notice Helper: mint tokens via processVAA using a MockWormholeCore
    function _mintViaProcessVAA(
        MockWormholeCore mockWormhole,
        address recipient,
        uint256 mintAmount,
        bytes memory vaaBytes
    ) internal {
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            abi.encode(recipient, mintAmount, chainId)
        );
        wormholeBridgeAdapterProxy.processVAA(vaaBytes);
    }

    /// @notice Helper: deploy MockWormholeCore, deploy new impl,
    ///         upgrade proxy via proxyAdmin.upgradeAndCall with initializeV3
    function _upgradeToV3() internal returns (MockWormholeCore mockWormhole) {
        mockWormhole = new MockWormholeCore();
        mockWormhole.setChainId(chainId); /// mock returns this chain's wormhole ID

        WormholeBridgeAdapter newImpl = new WormholeBridgeAdapter();

        bytes memory initData = abi.encodeWithSelector(
            WormholeBridgeAdapter.initializeV3.selector,
            address(mockWormhole)
        );

        vm.prank(proxyAdmin.owner());
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(wormholeBridgeAdapterProxy)),
            address(newImpl),
            initData
        );
    }

    function testInitializeV3SetsWormhole() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        assertEq(
            address(wormholeBridgeAdapterProxy.wormhole()),
            address(mockWormhole),
            "wormhole address not set after V3 upgrade"
        );
    }

    function testInitializeV3RevertsZeroAddress() public {
        WormholeBridgeAdapter newImpl = new WormholeBridgeAdapter();

        bytes memory initData = abi.encodeWithSelector(
            WormholeBridgeAdapter.initializeV3.selector,
            address(0)
        );

        vm.prank(proxyAdmin.owner());
        vm.expectRevert("WormholeBridgeAdapter: zero address");
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(address(wormholeBridgeAdapterProxy)),
            address(newImpl),
            initData
        );
    }

    function testInitializeV3RevertsDoubleInit() public {
        _upgradeToV3();

        vm.expectRevert("Initializable: contract is already initialized");
        wormholeBridgeAdapterProxy.initializeV3(address(1));
    }

    function testProcessVAARevertsWormholeNotSet() public {
        /// Without upgrading to V3, wormhole is address(0)
        /// calling parseAndVerifyVM on address(0) will revert
        vm.expectRevert();
        wormholeBridgeAdapterProxy.processVAA(hex"deadbeef");
    }

    function testProcessVAASuccess() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        bytes memory payload = abi.encode(to, amount, chainId);
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            payload
        );

        bytes memory vaaBytes = hex"aabbccdd";
        uint256 startingBalance = xwellProxy.balanceOf(to);

        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit BridgedIn(chainId, to, amount);

        wormholeBridgeAdapterProxy.processVAA(vaaBytes);

        assertEq(
            xwellProxy.balanceOf(to) - startingBalance,
            amount,
            "incorrect amount minted via processVAA"
        );
        assertTrue(
            wormholeBridgeAdapterProxy.processedVAAHashes(keccak256(vaaBytes)),
            "VAA hash not marked as processed"
        );
    }

    function testProcessVAARevertsInvalidSignature() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        mockWormhole.setStorage(
            false,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "invalid things",
            abi.encode(to, amount, chainId)
        );

        vm.expectRevert("invalid things");
        wormholeBridgeAdapterProxy.processVAA(hex"deadbeef");
    }

    function testProcessVAARevertsUntrustedEmitter() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        mockWormhole.setStorage(
            true,
            chainId,
            address(0xdead).toBytes(), /// untrusted emitter
            "",
            abi.encode(to, amount, chainId)
        );

        vm.expectRevert("WormholeBridgeAdapter: untrusted emitter");
        wormholeBridgeAdapterProxy.processVAA(hex"deadbeef");
    }

    function testProcessVAARevertsReplay() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        bytes memory payload = abi.encode(to, amount, chainId);
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            payload
        );

        bytes memory vaaBytes = hex"aabbccdd";

        /// First call succeeds
        wormholeBridgeAdapterProxy.processVAA(vaaBytes);

        /// Second call with same bytes should revert (same keccak256 hash)
        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        wormholeBridgeAdapterProxy.processVAA(vaaBytes);
    }

    function testProcessVAARevertsRateLimit() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        /// First VAA: drain the entire buffer
        uint256 maxBuffer = xwellProxy.buffer(
            address(wormholeBridgeAdapterProxy)
        );
        bytes memory payload1 = abi.encode(to, maxBuffer, chainId);
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            payload1
        );
        wormholeBridgeAdapterProxy.processVAA(hex"01");

        /// Second VAA: amount=1 should hit the rate limit
        bytes memory payload2 = abi.encode(to, uint256(1), chainId);
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            payload2
        );

        vm.expectRevert("RateLimited: rate limit hit");
        wormholeBridgeAdapterProxy.processVAA(hex"02");
    }

    function testBridgeCostUsesRelayerTryCatch() public {
        /// bridgeCost calls wormhole.messageFee() so V3 upgrade is required.
        /// MockWormholeReceiver.price() returns 0 so quoteEVMDeliveryPrice
        /// returns 0, and messageFee() returns 0 → bridgeCost returns 0.
        _upgradeToV3();
        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        assertEq(
            cost,
            0,
            "bridgeCost should use relayer try-catch and return 0"
        );
    }

    function testBridgeCostReturnsZeroWhenRelayerReverts() public {
        _upgradeToV3();

        /// After V3 upgrade, bridgeCost still uses the relayer try-catch.
        /// The MockWormholeReceiver is still etched, so it returns 0.
        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        assertEq(cost, 0, "bridgeCost should return 0 via try-catch");
    }

    function testBridgeOutPublishesDirectVAA() public {
        MockWormholeCore mockWormhole = _upgradeToV3();
        mockWormhole.setFee(0);

        /// Mint tokens to a user via processVAA so user has balance
        amount = externalChainBufferCap / 2;
        to = address(this);

        _mintViaProcessVAA(mockWormhole, to, amount, hex"aa03");

        /// Now bridge out via the new V3 path (publishMessage)
        uint256 bridgeAmount = amount / 2;
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), bridgeAmount);

        vm.expectEmit(
            true,
            true,
            true,
            true,
            address(wormholeBridgeAdapterProxy)
        );
        emit TokensSent(chainId, to, bridgeAmount);
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, bridgeAmount, to);
    }

    function testProcessVAARevertsWrongTargetChain() public {
        MockWormholeCore mockWormhole = _upgradeToV3();

        /// Payload encodes a different target chain than the mock's chainId().
        /// This simulates a VAA meant for Optimism (chain 24) being replayed on
        /// Base (chain 30, which is what the mock returns).
        uint16 wrongChainId = chainId + 1;
        bytes memory payload = abi.encode(to, amount, wrongChainId);
        mockWormhole.setStorage(
            true,
            chainId,
            address(wormholeBridgeAdapterProxy).toBytes(),
            "",
            payload
        );

        vm.expectRevert("WormholeBridgeAdapter: invalid target chain");
        wormholeBridgeAdapterProxy.processVAA(hex"cc");
    }
}

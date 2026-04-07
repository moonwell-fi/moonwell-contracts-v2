pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {MockWormholeReceiver} from "@test/mock/MockWormholeReceiver.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {Address} from "@utils/Address.sol";

contract WormholeUnwrapperAdapterUnitTest is BaseTest {
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
    address public to;

    /// @notice amount of tokens to mint
    uint256 public amount;

    /// relayer gas cost
    uint256 public immutable gasCost = 0.00001 * 1 ether;

    /// mock wormhole receiver
    MockWormholeReceiver public receiver;

    /// wormhole bridge unwrapper adapter logic contract
    WormholeUnwrapperAdapter unwrapper;

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

        testSetup();

        unwrapper = new WormholeUnwrapperAdapter();

        proxyAdmin.upgrade(
            ITransparentUpgradeableProxy(address(wormholeBridgeAdapterProxy)),
            address(unwrapper)
        );

        vm.prank(owner);
        WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
            .setLockbox(address(xerc20Lockbox));
        deal(address(well), address(xerc20Lockbox), 5_000_000_000 * 1e18);
    }

    function testOwnerCannotSetLockboxIfAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert("WormholeUnwrapperAdapter: lockbox already set");
        WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
            .setLockbox(address(xerc20Lockbox));

        assertEq(
            WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
                .lockbox(),
            address(xerc20Lockbox),
            "lockbox not set correctly"
        );
    }

    function testNonOwnerCannotSetLockbox() public {
        vm.expectRevert("Ownable: caller is not the owner");
        WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
            .setLockbox(address(xerc20Lockbox));
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

    /// receiveWormholeMessages is deprecated and should revert after V3 upgrade
    function testReceiveWormholeMessagesRevertsAfterV3() public {
        _initV3();

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

    /// @notice Helper: initialize V3 with a MockWormholeCore (fee=0, chainId set)
    function _initV3() internal returns (MockWormholeCore mockWormhole) {
        mockWormhole = new MockWormholeCore();
        mockWormhole.setFee(0);
        mockWormhole.setChainId(chainId);
        vm.prank(owner);
        WormholeBridgeAdapter(address(wormholeBridgeAdapterProxy)).initializeV3(
            address(mockWormhole)
        );
    }

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

    /// incorrect cost
    function testBridgeOutFailsIncorrectCost() public {
        MockWormholeCore mockWormhole = _initV3();
        mockWormhole.setFee(0);

        vm.deal(address(this), 1);
        vm.expectRevert("WormholeBridgeAdapter: cost not equal to quote");
        wormholeBridgeAdapterProxy.bridge{value: 1}(chainId, amount, to);
    }

    /// incorrect target chain
    function testBridgeOutFailsIncorrectTargetChain() public {
        MockWormholeCore mockWormhole = _initV3();
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
        _initV3();

        vm.expectRevert("ERC20: insufficient allowance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// not enough balance
    function testBridgeOutFailsNotEnoughBalance() public {
        _initV3();

        deal(address(xwellProxy), address(this), amount - 1);
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// not enough rate limit
    function testBridgeOutFailsNotEnoughBuffer() public {
        MockWormholeCore mockWormhole = _initV3();

        amount = externalChainBufferCap / 2;
        to = address(this);

        _mintViaProcessVAA(mockWormhole, to, amount, hex"aa01");

        amount = externalChainBufferCap;
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("RateLimited: buffer cap overflow");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount + 1, to);
    }

    function testBridgeOutSucceeds() public {
        MockWormholeCore mockWormhole = _initV3();

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
}

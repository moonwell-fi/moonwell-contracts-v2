pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {MockWormholeReceiver} from "@test/mock/MockWormholeReceiver.sol";
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

        unwrapper = new WormholeUnwrapperAdapter(address(0), address(0), address(0));

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

    /// receiveWormholeMessages failure tests
    /// value
    // TODO: migrate testReceiveWormholeMessageFailsWithValue to executeVAAv1 pattern

    /// not relayer address
    // TODO: migrate testReceiveWormholeMessageFailsNotRelayer to executeVAAv1 pattern

    /// already processed

    // TODO: migrate testAlreadyProcessedMessageReplayFails to executeVAAv1 pattern

    /// not trusted sender from external chain
    // TODO: migrate testReceiveWormholeMessageFailsNotTrustedExternalChain to executeVAAv1 pattern

    // TODO: migrate testReceiveWormholeMessageSucceeds to executeVAAv1 pattern

    /// bridge in, test not enough rate limit
    // TODO: migrate testBridgeInFailsRateLimitExhausted to executeVAAv1 pattern

    /// bridge out tests:

    /// incorrect cost
    function testBridgeOutFailsIncorrectCost() public {
        vm.deal(address(this), 1);
        vm.expectRevert("WormholeBridge: cost not equal to quote");
        wormholeBridgeAdapterProxy.bridge{value: 1}(chainId, amount, to);
    }

    /// incorrect target chain
    function testBridgeOutFailsIncorrectTargetChain() public {
        vm.expectRevert("WormholeBridge: invalid target chain");
        wormholeBridgeAdapterProxy.bridge{value: 0}(
            chainId + 1, /// invalid chain id
            amount,
            to
        );
    }

    /// not enough approvals
    function testBridgeOutFailsNoApproval() public {
        vm.expectRevert("ERC20: insufficient allowance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    /// not enough balance
    function testBridgeOutFailsNotEnoughBalance() public {
        deal(address(xwellProxy), address(this), amount - 1);
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount, to);
    }

    // TODO: migrate testBridgeOutFailsNotEnoughBuffer to executeVAAv1 pattern

    // TODO: migrate testBridgeOutSucceeds to executeVAAv1 pattern - needs bridge-in first
    function _disabled_testBridgeOutSucceeds() internal {
        amount = externalChainBufferCap / 2;
        to = address(this);

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

pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MockCoreBridgeForAdapter} from "@test/mock/MockCoreBridgeForAdapter.sol";
import {MockExecutorQuoterRouter} from "@test/mock/MockExecutorQuoterRouter.sol";

contract WormholeUnwrapperAdapterUnitTest is BaseTest {
    /// events
    event BridgedOut(
        uint256 indexed dstChainId,
        address indexed bridgeUser,
        address indexed tokenReceiver,
        uint256 amount
    );

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

    event TargetAddressUpdated(
        uint16 indexed dstChainId,
        address indexed target
    );

    event GasLimitUpdated(uint96 oldGasLimit, uint96 newGasLimit);

    /// state variables
    address public to;
    uint256 public amount;

    /// wormhole bridge unwrapper adapter logic contract
    WormholeUnwrapperAdapter unwrapper;

    function setUp() public override {
        super.setUp();
        to = address(999999999999999);
        amount = 100 * 1e18;

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
    /// ------------------- Lockbox Tests ----------------------
    /// --------------------------------------------------------

    function testOwnerCannotSetLockboxIfAlreadySet() public {
        vm.prank(owner);
        vm.expectRevert("WormholeUnwrapperAdapter: lockbox already set");
        WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
            .setLockbox(address(xerc20Lockbox));
    }

    function testNonOwnerCannotSetLockbox() public {
        vm.expectRevert("Ownable: caller is not the owner");
        WormholeUnwrapperAdapter(address(wormholeBridgeAdapterProxy))
            .setLockbox(address(xerc20Lockbox));
    }

    /// --------------------------------------------------------
    /// -------------------- Setup Tests -----------------------
    /// --------------------------------------------------------

    function testSetup() public view {
        assertEq(wormholeBridgeAdapterProxy.owner(), owner);
        assertEq(
            address(wormholeBridgeAdapterProxy.wormhole()),
            address(mockCoreBridge)
        );
        assertEq(
            address(wormholeBridgeAdapterProxy.executorQuoterRouter()),
            address(mockExecutorQuoterRouter)
        );
        assertTrue(
            wormholeBridgeAdapterProxy.isTrustedSender(
                chainId,
                address(wormholeBridgeAdapterProxy)
            )
        );
        assertEq(
            wormholeBridgeAdapterProxy.targetAddress(chainId),
            address(wormholeBridgeAdapterProxy)
        );
        assertEq(
            address(xwellProxy),
            address(wormholeBridgeAdapterProxy.xERC20())
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
                )
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
    /// ----------- executeVAAv1 Tests (Unwrapper) -------------
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

    function testExecuteVAAv1SucceedsUnwrapsToWell() public {
        uint256 startingWellBalance = well.balanceOf(to);
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
        emit BridgedIn(chainId, address(wormholeBridgeAdapterProxy), amount);

        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);

        assertEq(well.balanceOf(to) - startingWellBalance, amount);
        assertEq(xwellProxy.totalSupply(), startingTotalSupply);
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
}

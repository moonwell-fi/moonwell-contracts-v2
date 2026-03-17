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

    function setUp() public override {
        super.setUp();
        to = address(999999999999999);
        amount = 100 * 1e18;
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------- Helper Functions -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// @notice Set up mock core bridge to return a valid VAA with given params
    /// @param emitterChainId the chain the message was emitted from
    /// @param emitterAddress the address that emitted the message (bytes32)
    /// @param sequence the VAA sequence number
    /// @param payload the VAA payload
    /// @return encodedVaa fake encoded VAA bytes (just used as passthrough to mock)
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
        /// The actual bytes don't matter — the mock ignores them and returns preset data
        encodedVaa = abi.encode(
            "mock-vaa",
            emitterChainId,
            emitterAddress,
            sequence
        );
    }

    /// @notice Bridge in tokens via executeVAAv1 using a valid VAA from the trusted adapter
    /// @param sequence the VAA sequence number (each call must use a unique sequence)
    function _bridgeInViaVaa(uint64 sequence) internal {
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount);
        bytes memory encodedVaa = _setupVaa(
            chainId,
            emitterAddr,
            sequence,
            payload
        );

        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// -------------------- Setup Tests -----------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    function testSetup() public view {
        assertEq(wormholeBridgeAdapterProxy.owner(), owner, "invalid owner");
        assertEq(
            address(wormholeBridgeAdapterProxy.wormholeRelayer()),
            address(mockCoreBridge),
            "invalid wormhole relayer / core bridge"
        );
        assertEq(
            address(wormholeBridgeAdapterProxy.coreBridge()),
            address(mockCoreBridge),
            "invalid core bridge"
        );
        assertEq(
            address(wormholeBridgeAdapterProxy.executorQuoterRouter()),
            address(mockExecutorQuoterRouter),
            "invalid executor quoter router"
        );
        assertEq(
            wormholeBridgeAdapterProxy.wormholeChainId(),
            chainId,
            "invalid wormhole chain id"
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

    function testInitializeV3FailsAlreadyInitialized() public {
        vm.expectRevert("Initializable: contract is already initialized");
        wormholeBridgeAdapterProxy.initializeV3(
            address(mockCoreBridge),
            address(mockExecutorQuoterRouter),
            address(mockExecutorQuoterRouter),
            address(0),
            chainId
        );
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ------------------- ACL Failure Tests ------------------
    /// --------------------------------------------------------
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
    /// --------------------------------------------------------
    /// ------------------- ACL Success Tests ------------------
    /// --------------------------------------------------------
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
        vm.expectRevert(
            abi.encodeWithSelector(
                WormholeTrustedSender.EnumerableSetError.selector
            )
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                WormholeTrustedSender.EnumerableSetError.selector
            )
        );
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

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// --------------- Initialization Tests -------------------
    /// --------------------------------------------------------
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
    /// --------------------------------------------------------
    /// ----------- executeVAAv1 Failure Tests -----------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// msg.value must be 0
    function testExecuteVAAv1FailsWithValue() public {
        vm.deal(address(this), 100);
        vm.expectRevert("WormholeBridge: no value allowed");
        wormholeBridgeAdapterProxy.executeVAAv1{value: 100}(bytes("fake-vaa"));
    }

    /// invalid VAA (core bridge returns valid=false)
    function testExecuteVAAv1FailsInvalidVaa() public {
        mockCoreBridge.setValid(false, "bad signature");
        bytes memory encodedVaa = bytes("invalid-vaa");

        vm.expectRevert("bad signature");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// untrusted sender
    function testExecuteVAAv1FailsUntrustedSender() public {
        bytes32 untrustedEmitter = bytes32(uint256(uint160(address(0xdead))));
        bytes memory payload = abi.encode(to, amount);
        bytes memory encodedVaa = _setupVaa(
            chainId,
            untrustedEmitter,
            0,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// replay — same sequence number
    function testExecuteVAAv1FailsReplay() public {
        /// first call succeeds
        _bridgeInViaVaa(0);

        /// second call with same sequence should fail
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 0, payload);

        vm.expectRevert();
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ----------- executeVAAv1 Success Tests -----------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    function testExecuteVAAv1Succeeds() public {
        uint256 startingBalance = xwellProxy.balanceOf(to);
        uint256 startingTotalSupply = xwellProxy.totalSupply();

        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount);
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

        assertEq(
            xwellProxy.balanceOf(to) - startingBalance,
            amount,
            "incorrect amount received"
        );
        assertEq(
            xwellProxy.totalSupply() - startingTotalSupply,
            amount,
            "incorrect total supply increase"
        );
    }

    function testExecuteVAAv1SucceedsMultipleSequences() public {
        uint256 startingBalance = xwellProxy.balanceOf(to);

        _bridgeInViaVaa(0);
        _bridgeInViaVaa(1);
        _bridgeInViaVaa(2);

        assertEq(
            xwellProxy.balanceOf(to) - startingBalance,
            amount * 3,
            "incorrect total amount received after 3 bridge-ins"
        );
    }

    /// bridge in, test not enough rate limit
    function testBridgeInFailsRateLimitExhausted() public {
        amount = xwellProxy.buffer(address(wormholeBridgeAdapterProxy));
        _bridgeInViaVaa(0);

        amount = 1;
        bytes32 emitterAddr = bytes32(
            uint256(uint160(address(wormholeBridgeAdapterProxy)))
        );
        bytes memory payload = abi.encode(to, amount);
        bytes memory encodedVaa = _setupVaa(chainId, emitterAddr, 1, payload);

        vm.expectRevert("RateLimited: rate limit hit");
        wormholeBridgeAdapterProxy.executeVAAv1(encodedVaa);
    }

    /// --------------------------------------------------------
    /// --------------------------------------------------------
    /// ---------- Deprecated receiveWormholeMessages ----------
    /// --------------------------------------------------------
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
    /// --------------------------------------------------------
    /// ------------------- Bridge Out Tests -------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    /// incorrect cost
    function testBridgeOutFailsIncorrectCost() public {
        /// set a non-zero quote so msg.value mismatch triggers
        mockExecutorQuoterRouter.setQuote(0.001 ether);
        mockCoreBridge.setMessageFee(0.0001 ether);

        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        vm.deal(address(this), cost + 1);

        vm.expectRevert("WormholeBridge: cost not equal to quote");
        wormholeBridgeAdapterProxy.bridge{value: cost + 1}(chainId, amount, to);
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

    /// not enough rate limit
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
    /// --------------------------------------------------------
    /// ------------------- Bridge Cost Tests ------------------
    /// --------------------------------------------------------
    /// --------------------------------------------------------

    function testBridgeCostReturnsQuotePlusMessageFee() public {
        mockExecutorQuoterRouter.setQuote(0.01 ether);
        mockCoreBridge.setMessageFee(0.001 ether);

        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId);
        assertEq(
            cost,
            0.011 ether,
            "bridge cost should be quote + message fee"
        );
    }

    function testBridgeCostReturnsZeroWhenQuoteFails() public {
        /// quote will revert since targetAddress for chainId+1 is zero
        uint256 cost = wormholeBridgeAdapterProxy.bridgeCost(chainId + 1);
        assertEq(cost, 0, "bridge cost should be 0 for unknown chain");
    }
}

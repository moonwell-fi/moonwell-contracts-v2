pragma solidity 0.8.19;

import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

import {Address} from "@utils/Address.sol";
import {VaaHelper} from "@test/helper/VaaHelper.sol";
import {ICoreBridge} from "wormhole-sdk/interfaces/ICoreBridge.sol";
import {toUniversalAddress} from "wormhole-sdk/Utils.sol";

contract WormholeBridgeAdapterUnitTest is BaseTest {
    using Address for address;

    /// xerc20 bridge adapter events

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
    address to;
    uint256 amount;
    uint64 vaaSeq;

    function setUp() public override {
        super.setUp();
        to = address(999999999999999);
        amount = 100 * 1e18;
    }

    /// @dev Craft a valid VAA to deliver tokens to the bridge adapter
    function _craftBridgeInVaa(
        uint16 destinationChainId,
        address recipient,
        uint256 bridgeAmount,
        uint16 emitterChain,
        address emitter
    ) internal returns (bytes memory) {
        bytes memory payload = abi.encode(destinationChainId, recipient, bridgeAmount);
        return VaaHelper.craftVaa(
            wormholeBridgeAdapterProxy.coreBridge(),
            emitterChain,
            emitter,
            vaaSeq++,
            payload
        );
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

    /// initialization
    function testInitializeFailsArrayLengthMismatch() public {
        ProxyAdmin admin = new ProxyAdmin();
        (, , , , address wormholeAdapterProxy, ) = deployMoonbeamSystem(
            address(well),
            address(admin),
            address(0),
            address(0),
            address(0)
        );
        wormholeBridgeAdapterProxy = WormholeBridgeAdapter(
            wormholeAdapterProxy
        );

        vm.expectRevert("WormholeBridge: array length mismatch");
        wormholeBridgeAdapterProxy.initialize(
            address(xwellProxy),
            owner,
            new uint16[](1),
            new address[](0)
        );
    }

    /// executeVAAv1 failure tests

    /// value
    function testExecuteVAAv1FailsWithValue() public {
        bytes memory vaa = _craftBridgeInVaa(
            chainId,
            to,
            amount,
            chainId,
            address(wormholeBridgeAdapterProxy)
        );

        vm.deal(address(this), 100);
        vm.expectRevert("WormholeBridge: no value allowed");
        wormholeBridgeAdapterProxy.executeVAAv1{value: 100}(vaa);
    }

    /// not trusted sender
    function testExecuteVAAv1FailsNotTrustedSender() public {
        // Craft VAA from an untrusted emitter
        bytes memory payload = abi.encode(chainId, to, amount);
        bytes memory vaa = VaaHelper.craftVaa(
            wormholeBridgeAdapterProxy.coreBridge(),
            chainId,
            address(0xdead), // untrusted sender
            vaaSeq++,
            payload
        );

        vm.expectRevert("WormholeBridge: sender not trusted");
        wormholeBridgeAdapterProxy.executeVAAv1(vaa);
    }

    /// replay protection
    function testReplayProtectionPreventsDoubleProcessing() public {
        testExecuteVAAv1Succeeds();

        // Try to replay the same sequence - craft a new VAA but with same emitter and sequence 0
        // Use a manually decremented sequence to get the same one
        uint64 prevSeq = vaaSeq; // vaaSeq is already incremented past 0
        vaaSeq = 0; // reset to replay sequence 0
        bytes memory vaa = _craftBridgeInVaa(
            chainId,
            to,
            amount,
            chainId,
            address(wormholeBridgeAdapterProxy)
        );
        vaaSeq = prevSeq; // restore

        vm.expectRevert(); // AlreadyProcessed custom error
        wormholeBridgeAdapterProxy.executeVAAv1(vaa);
    }

    /// destination chain mismatch
    function testExecuteVAAv1FailsDestinationChainMismatch() public {
        // Craft VAA with wrong destination chain in payload
        bytes memory vaa = _craftBridgeInVaa(
            chainId + 1, // wrong destination
            to,
            amount,
            chainId,
            address(wormholeBridgeAdapterProxy)
        );

        vm.expectRevert("WormholeBridge: destination chain mismatch");
        wormholeBridgeAdapterProxy.executeVAAv1(vaa);
    }

    function testExecuteVAAv1Succeeds() public {
        uint256 startingBalance = xwellProxy.balanceOf(to);
        uint256 startingTotalSupply = xwellProxy.totalSupply();

        bytes memory vaa = _craftBridgeInVaa(
            chainId,
            to,
            amount,
            chainId,
            address(wormholeBridgeAdapterProxy)
        );

        vm.expectEmit(true, true, true, true, address(wormholeBridgeAdapterProxy));
        emit BridgedIn(chainId, to, amount);
        wormholeBridgeAdapterProxy.executeVAAv1(vaa);

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

    /// bridge in, test not enough rate limit
    function testBridgeInFailsRateLimitExhausted() public {
        amount = xwellProxy.buffer(address(wormholeBridgeAdapterProxy));
        testExecuteVAAv1Succeeds();

        amount = 1;
        bytes memory vaa = _craftBridgeInVaa(
            chainId,
            to,
            amount,
            chainId,
            address(wormholeBridgeAdapterProxy)
        );

        vm.expectRevert("RateLimited: rate limit hit");
        wormholeBridgeAdapterProxy.executeVAAv1(vaa);
    }

    /// bridge out tests:

    /// incorrect target chain
    function testBridgeOutFailsIncorrectTargetChain() public {
        vm.expectRevert("WormholeBridge: invalid target chain");
        wormholeBridgeAdapterProxy.bridge{value: 0}(
            chainId + 1,
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

        testExecuteVAAv1Succeeds();

        amount = externalChainBufferCap;
        xwellProxy.approve(address(wormholeBridgeAdapterProxy), amount);

        vm.expectRevert("RateLimited: buffer cap overflow");
        wormholeBridgeAdapterProxy.bridge{value: 0}(chainId, amount + 1, to);
    }
}

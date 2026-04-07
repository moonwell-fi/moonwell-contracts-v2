// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Address} from "@utils/Address.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {MockExecutorQuoterRouter} from "@test/mock/MockExecutorQuoterRouter.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, BASE_FORK_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract xWellIntegrationTest is PostProposalCheck {
    using ChainIds for uint256;
    using Address for address;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
    }

    function testReinitializeFails() public {
        vm.expectRevert("Initializable: contract is already initialized");
        xwell.initialize(
            "WELL",
            "WELL",
            address(1),
            new MintLimits.RateLimitMidPointInfo[](0),
            0,
            address(0)
        );

        vm.expectRevert();
        wormholeAdapter.initialize(
            address(1),
            address(1),
            address(1),
            new uint16[](0),
            new address[](0)
        );
    }

    function testSetup() public view {
        address externalChainAddress = wormholeAdapter.targetAddress(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        assertEq(
            externalChainAddress,
            address(wormholeAdapter),
            "incorrect target address config"
        );
        bytes32[] memory externalAddresses = wormholeAdapter.allTrustedSenders(
            MOONBEAM_WORMHOLE_CHAIN_ID
        );
        assertEq(externalAddresses.length, 1, "incorrect trusted senders");
        assertEq(
            externalAddresses[0],
            address(wormholeAdapter).toBytes(),
            "incorrect actual trusted senders"
        );
        assertTrue(
            wormholeAdapter.isTrustedSender(
                uint16(MOONBEAM_WORMHOLE_CHAIN_ID),
                address(wormholeAdapter)
            ),
            "self on moonbeam not trusted sender"
        );
    }

    /// @notice After x50, validate V5 Executor state on Base
    function testExecutorStateAfterV5Upgrade() public view {
        assertTrue(
            address(wormholeAdapter.executor()) != address(0),
            "Base: executor not set after V5"
        );
        assertEq(
            wormholeAdapter.wormholeChainId(),
            uint16(BASE_WORMHOLE_CHAIN_ID),
            "Base: wormholeChainId mismatch"
        );
        /// Base has on-chain quoter
        assertTrue(
            address(wormholeAdapter.executorQuoterRouter()) != address(0),
            "Base: executorQuoterRouter should be set"
        );
    }

    /// @notice Bridge out using the off-chain signed quote path.
    ///         We etch a mock executor onto the real executor address so that
    ///         requestExecution succeeds without needing a valid signed quote.
    function testBridgeOutSuccess() public {
        uint256 mintAmount = testBridgeInSuccess(startingWellAmount);

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = block.chainid.toMoonbeamWormholeChainId();

        /// Etch MockExecutorQuoterRouter onto the real executor address
        /// so requestExecution succeeds without real Wormhole infrastructure
        address executorAddr = address(wormholeAdapter.executor());
        MockExecutorQuoterRouter mockExecutor = new MockExecutorQuoterRouter();
        vm.etch(executorAddr, address(mockExecutor).code);

        uint256 messageFee = wormholeAdapter.wormhole().messageFee();
        uint256 executorFee = 0.001 ether;
        vm.deal(user, messageFee + executorFee);

        vm.startPrank(user);
        xwell.approve(address(wormholeAdapter), mintAmount);
        wormholeAdapter.bridge{value: messageFee + executorFee}(
            dstChainId,
            mintAmount,
            user,
            hex"deadbeef" // off-chain signed quote
        );
        vm.stopPrank();

        uint256 endingXWellBalance = xwell.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));

        assertEq(endingBuffer, startingBuffer + mintAmount, "buffer incorrect");
        assertEq(
            endingXWellBalance,
            startingXWellBalance - mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            endingXWellTotalSupply,
            startingXWellTotalSupply - mintAmount,
            "total xWELL supply incorrect"
        );
    }

    function testBridgeInSuccess(uint256 mintAmount) public returns (uint256) {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        /// Swap wormhole core with mock for executeVAAv1 testing.
        /// After x50, the adapter is V5 with Executor framework.
        bytes memory vaaBytes;
        {
            MockWormholeCore mockWormhole = new MockWormholeCore();
            mockWormhole.setChainId(uint16(BASE_WORMHOLE_CHAIN_ID));

            /// Override the wormhole core address (slot 156) with the mock
            vm.store(
                address(wormholeAdapter),
                bytes32(uint256(156)),
                bytes32(uint256(uint160(address(mockWormhole))))
            );

            mockWormhole.setStorage(
                true,
                uint16(MOONBEAM_WORMHOLE_CHAIN_ID),
                address(wormholeAdapter).toBytes(),
                "",
                abi.encode(user, mintAmount)
            );

            vaaBytes = abi.encode("bridge-in-vaa", mintAmount);
        }

        /// --- Bridge in via executeVAAv1 ---
        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        wormholeAdapter.executeVAAv1(vaaBytes);

        assertEq(
            xwell.balanceOf(user),
            startingXWellBalance + mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply + mintAmount,
            "total xWELL supply incorrect"
        );
        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer - mintAmount,
            "buffer incorrect"
        );

        return mintAmount;
    }
}

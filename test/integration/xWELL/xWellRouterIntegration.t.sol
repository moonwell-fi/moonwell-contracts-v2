// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MockExecutorQuoterRouter} from "@test/mock/MockExecutorQuoterRouter.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/// @notice Tests the xWELLRouter on Moonbeam after the V5 (Executor framework)
///         upgrade. Moonbeam has no on-chain quoter, so the only working
///         bridge-out path is the off-chain signed-quote `bridge(uint16,...)`
///         overload. Uses plain `Test` so the moonbeam-integration CI
///         workflow (--fork-url moonbeam, only Moonbeam fork) can run it.
contract xWellRouterMoonbeamTest is Test {
    /// @notice address registry — read from chains/1284.json
    Addresses public addresses;

    /// @notice xWELL token
    xWELL public xwell;

    /// @notice WELL token
    IERC20 public well;

    /// @notice wormhole bridge adapter (V5)
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice xWELL lockbox
    XERC20Lockbox public lockbox;

    /// @notice fresh router pointing at the live (post-V5) adapter
    xWELLRouter public router;

    /// @notice fixed test user — avoids any state on `address(this)` from
    ///         PostProposalCheck setup
    address public constant USER = address(0xCAFE);

    /// @notice executor fee used in tests (would normally come from signed quote)
    uint256 public constant EXECUTOR_FEE = 0.001 ether;

    /// @notice signed quote stub — the real flow validates this off-chain
    bytes public constant SIGNED_QUOTE = hex"deadbeef";

    /// @notice whether USER's receive() reverts on refund attempts
    bool public fallbackReverts;

    /// @notice mirror of the router event for vm.expectEmit
    event BridgeOutSuccess(
        address indexed to,
        uint16 indexed destWormholeChainId,
        uint256 amount
    );

    function setUp() public {
        addresses = new Addresses();

        well = IERC20(addresses.getAddress("GOVTOKEN"));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        lockbox = XERC20Lockbox(addresses.getAddress("xWELL_LOCKBOX"));

        router = new xWELLRouter(
            address(xwell),
            address(well),
            address(lockbox),
            address(wormholeAdapter)
        );

        /// Etch a mock executor onto the live executor address so
        /// requestExecution accepts the off-chain signed quote.
        address executorAddr = address(wormholeAdapter.executor());
        MockExecutorQuoterRouter mockExecutor = new MockExecutorQuoterRouter();
        vm.etch(executorAddr, address(mockExecutor).code);

        fallbackReverts = false;

        /// Set this contract's `receive()` to optionally revert so refund
        /// tests can assert the router-level failure path.
        vm.etch(USER, address(this).code);
    }

    function _value() internal view returns (uint256) {
        return wormholeAdapter.wormhole().messageFee() + EXECUTOR_FEE;
    }

    function _boundMintAmount(
        uint256 mintAmount
    ) internal view returns (uint256) {
        uint256 buffer = xwell.buffer(address(wormholeAdapter));
        uint256 bufferCap = xwell.bufferCap(address(wormholeAdapter));
        return _bound(mintAmount, 1, bufferCap - buffer);
    }

    /// --------------------------------------------------------
    /// ------------------- Setup Tests ------------------------
    /// --------------------------------------------------------

    function testSetup() public view {
        assertEq(
            address(router.xwell()),
            address(xwell),
            "router.xwell() incorrect"
        );
        assertEq(
            address(router.well()),
            address(well),
            "router.well() incorrect"
        );
        assertEq(
            address(router.lockbox()),
            address(lockbox),
            "router.lockbox() incorrect"
        );
        assertEq(
            address(router.wormholeBridge()),
            address(wormholeAdapter),
            "router.wormholeBridge() incorrect"
        );
    }

    /// --------------------------------------------------------
    /// ----------- Signed-Quote Bridge Out Success ------------
    /// --------------------------------------------------------

    function testBridgeToSenderSucceeds() public {
        _bridgeToSenderSucceeds(_boundMintAmount(300_000_000 * 1e18));
    }

    function testBridgeToSenderFuzz(uint256 mintAmount) public {
        _bridgeToSenderSucceeds(_boundMintAmount(mintAmount));
    }

    function testBridgeToRecipientFuzz(
        uint256 mintAmount,
        uint256 glmrAmount
    ) public {
        mintAmount = _boundMintAmount(mintAmount);
        uint256 totalValue = _value();
        glmrAmount = _bound(glmrAmount, totalValue, type(uint128).max);

        deal(address(well), USER, mintAmount);
        vm.deal(USER, glmrAmount);

        uint256 startingXWellSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));
        uint256 startingLockboxWell = well.balanceOf(address(lockbox));

        vm.startPrank(USER);
        well.approve(address(router), mintAmount);

        vm.expectEmit(true, true, true, true, address(router));
        emit BridgeOutSuccess(USER, BASE_WORMHOLE_CHAIN_ID, mintAmount);

        router.bridgeToRecipient{value: glmrAmount}(
            USER,
            mintAmount,
            BASE_WORMHOLE_CHAIN_ID,
            SIGNED_QUOTE
        );
        vm.stopPrank();

        /// Mock executor consumes any value forwarded by the adapter, so the
        /// router never has leftover. The caller only spends the messageFee
        /// portion of the executor request — the remainder is forwarded
        /// without checking it equals the actual quote.
        assertEq(address(router).balance, 0, "router holds leftover GLMR");
        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer + mintAmount,
            "buffer did not increase by burn amount"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellSupply,
            "xWELL totalSupply changed (mint then burn should net to zero)"
        );
        assertEq(
            well.balanceOf(address(lockbox)),
            startingLockboxWell + mintAmount,
            "lockbox did not receive WELL"
        );
    }

    function _bridgeToSenderSucceeds(uint256 mintAmount) internal {
        deal(address(well), USER, mintAmount);
        uint256 totalValue = _value();
        vm.deal(USER, totalValue);

        uint256 startingXWellSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));
        uint256 startingLockboxWell = well.balanceOf(address(lockbox));

        vm.startPrank(USER);
        well.approve(address(router), mintAmount);

        vm.expectEmit(true, true, true, true, address(router));
        emit BridgeOutSuccess(USER, BASE_WORMHOLE_CHAIN_ID, mintAmount);

        router.bridgeToSender{value: totalValue}(
            mintAmount,
            BASE_WORMHOLE_CHAIN_ID,
            SIGNED_QUOTE
        );
        vm.stopPrank();

        assertEq(address(router).balance, 0, "router holds leftover GLMR");
        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer + mintAmount,
            "buffer did not increase by burn amount"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellSupply,
            "xWELL totalSupply changed (mint then burn should net to zero)"
        );
        assertEq(
            well.balanceOf(address(lockbox)),
            startingLockboxWell + mintAmount,
            "lockbox did not receive WELL"
        );
    }

    /// --------------------------------------------------------
    /// ----------- Signed-Quote Bridge Out Failure ------------
    /// --------------------------------------------------------

    function testBridgeFailsNoApproval() public {
        uint256 mintAmount = 1_000e18;
        deal(address(well), USER, mintAmount);
        uint256 totalValue = _value();
        vm.deal(USER, totalValue);

        vm.prank(USER);
        vm.expectRevert(
            "Well::transferFrom: transfer amount exceeds spender allowance"
        );
        router.bridgeToSender{value: totalValue}(
            mintAmount,
            BASE_WORMHOLE_CHAIN_ID,
            SIGNED_QUOTE
        );
    }

    function testBridgeFailsNoBalance() public {
        uint256 mintAmount = 1_000e18;
        uint256 totalValue = _value();
        vm.deal(USER, totalValue);

        vm.startPrank(USER);
        well.approve(address(router), mintAmount);
        vm.expectRevert(
            "Well::_transferTokens: transfer amount exceeds balance"
        );
        router.bridgeToSender{value: totalValue}(
            mintAmount,
            BASE_WORMHOLE_CHAIN_ID,
            SIGNED_QUOTE
        );
        vm.stopPrank();
    }

    function testBridgeFailsZeroAmount() public {
        uint256 totalValue = _value();
        vm.deal(USER, totalValue);

        vm.prank(USER);
        vm.expectRevert("MintLimits: deplete amount cannot be 0");
        router.bridgeToSender{value: totalValue}(
            0,
            BASE_WORMHOLE_CHAIN_ID,
            SIGNED_QUOTE
        );
    }

    function testBridgeFailsInvalidTargetChain() public {
        uint256 mintAmount = 1_000e18;
        deal(address(well), USER, mintAmount);
        uint256 totalValue = _value();
        vm.deal(USER, totalValue);

        /// Pick an arbitrary unconfigured chain id. Moonbeam's adapter only
        /// has Base and Optimism (and post-PR-624, Ethereum) targets — 9999
        /// is guaranteed unset.
        uint16 unconfiguredChain = 9999;

        vm.startPrank(USER);
        well.approve(address(router), mintAmount);
        vm.expectRevert("WormholeBridge: invalid target chain");
        router.bridgeToSender{value: totalValue}(
            mintAmount,
            unconfiguredChain,
            SIGNED_QUOTE
        );
        vm.stopPrank();
    }

    /// USER is etched with this contract's bytecode so we can toggle its
    /// receive() behavior between accepting and reverting.
    receive() external payable {
        require(!fallbackReverts, "fallback reverted");
    }
}

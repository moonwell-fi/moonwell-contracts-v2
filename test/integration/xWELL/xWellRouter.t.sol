// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

contract xWellRouterTest is Test, ChainIds {
    /// @notice addresses contract, stores all addresses
    Addresses public addresses;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice well token contract
    IERC20 public well;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice xWELL router contract
    xWELLRouter public router;

    /// @notice xWELL lockbox contract
    XERC20Lockbox public lockbox;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    uint16 public constant wormholeMoonbeamChainid =
        uint16(moonBeamWormholeChainId);

    /// @notice event emitted when WELL is bridged to xWELL via the base chain
    event BridgeOutSuccess(address indexed to, uint256 amount);

    function setUp() public {
        addresses = new Addresses();

        well = IERC20(addresses.getAddress("WELL"));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        lockbox = XERC20Lockbox(addresses.getAddress("xWELL_LOCKBOX"));

        router = new xWELLRouter(
            address(xwell),
            addresses.getAddress("WELL"),
            addresses.getAddress("xWELL_LOCKBOX"),
            address(wormholeAdapter)
        );
    }

    function testSetup() public {
        assertEq(
            address(router.xwell()),
            address(xwell),
            "Xwell address incorrect"
        );
        assertEq(
            address(router.well()),
            addresses.getAddress("WELL"),
            "Well address incorrect"
        );
        assertEq(
            address(router.lockbox()),
            addresses.getAddress("xWELL_LOCKBOX"),
            "Lockbox address incorrect"
        );
        assertEq(
            address(router.wormholeBridge()),
            address(wormholeAdapter),
            "Wormhole bridge address incorrect"
        );
        assertEq(
            router.baseWormholeChainId(),
            baseWormholeChainId,
            "Base wormhole chain id incorrect"
        );
    }

    function testBridgeOutNoApprovalFails() public {
        uint256 mintAmount = 100_000_000 * 1e18;

        deal(address(well), address(this), mintAmount);
        uint256 bridgeCost = router.bridgeCost();

        vm.deal(address(this), bridgeCost);

        vm.expectRevert(
            "Well::transferFrom: transfer amount exceeds spender allowance"
        );
        router.bridgeToBase{value: bridgeCost}(mintAmount);
    }

    function testBridgeOutNoBalanceFails() public {
        uint256 mintAmount = 100_000_000 * 1e18;

        uint256 bridgeCost = router.bridgeCost();

        vm.deal(address(this), bridgeCost);
        well.approve(address(router), mintAmount);

        vm.expectRevert(
            "Well::_transferTokens: transfer amount exceeds balance"
        );
        router.bridgeToBase{value: bridgeCost}(mintAmount);
    }

    function testBridgeOutSuccess() public {
        testBridgeOutSuccess(300_000_000 * 1e18);
    }

    function testBridgeOutToSuccess(
        uint256 mintAmount
    ) public returns (uint256) {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        uint256 startingXWellBalance = xwell.balanceOf(address(this));
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        deal(address(well), address(this), mintAmount);
        uint256 bridgeCost = router.bridgeCost();
        vm.deal(address(this), bridgeCost);
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingLockboxWellBalance = well.balanceOf(address(lockbox));

        well.approve(address(router), mintAmount);
        vm.expectEmit(true, true, true, true, address(router));
        emit BridgeOutSuccess(address(this), mintAmount);
        router.bridgeToBase{value: bridgeCost}(address(this), mintAmount);

        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer + mintAmount,
            "incorrect buffer"
        );
        assertEq(
            xwell.balanceOf(address(this)),
            startingXWellBalance,
            "incorrect user xwell balance"
        );
        assertEq(
            well.balanceOf(address(this)),
            startingWellBalance - mintAmount,
            "incorrect user well balance"
        );
        assertEq(
            well.balanceOf(address(lockbox)),
            startingLockboxWellBalance + mintAmount,
            "incorrect lockbox well balance"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply,
            "incorrect xwell total supply"
        );
        return mintAmount;
    }

    function testBridgeOutSuccess(uint256 mintAmount) public returns (uint256) {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        uint256 startingXWellBalance = xwell.balanceOf(address(this));
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        deal(address(well), address(this), mintAmount);
        uint256 bridgeCost = router.bridgeCost();
        vm.deal(address(this), bridgeCost);
        uint256 startingWellBalance = well.balanceOf(address(this));
        uint256 startingLockboxWellBalance = well.balanceOf(address(lockbox));

        well.approve(address(router), mintAmount);
        vm.expectEmit(true, true, true, true, address(router));
        emit BridgeOutSuccess(address(this), mintAmount);
        router.bridgeToBase{value: bridgeCost}(mintAmount);

        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer + mintAmount,
            "incorrect buffer"
        );
        assertEq(
            xwell.balanceOf(address(this)),
            startingXWellBalance,
            "incorrect user xwell balance"
        );
        assertEq(
            well.balanceOf(address(this)),
            startingWellBalance - mintAmount,
            "incorrect user well balance"
        );
        assertEq(
            well.balanceOf(address(lockbox)),
            startingLockboxWellBalance + mintAmount,
            "incorrect lockbox well balance"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply,
            "incorrect xwell total supply"
        );
        return mintAmount;
    }
}

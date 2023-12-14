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
    }

    function testBridgeOutSuccess() public {}

    function testBridgeOutSuccess(uint256 mintAmount) public returns (uint256) {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        deal(address(well), address(this), mintAmount);
        uint256 bridgeCost = router.bridgeCost();
        vm.deal(address(this), bridgeCost);

        well.approve(address(router), mintAmount);
        router.bridgeToBase{value: bridgeCost}(mintAmount);

        return mintAmount;
    }
}

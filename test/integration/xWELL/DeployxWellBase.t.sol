// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {mipb12Base} from "@protocol/proposals/mips/mip-b12/mip-b12-base.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

contract DeployxWellBaseTest is mipb12Base {
    /// @notice addresses contract, stores all addresses
    Addresses public addresses;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    function setUp() public {
        addresses = new Addresses();

        deploy(addresses, address(0));

        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
    }

    function testBridgeOutSuccess() public {
        uint256 mintAmount = testBridgeInSuccess(startingWellAmount);

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = chainIdToWormHoleId[
            sendingChainIdToReceivingChainId[block.chainid]
        ];

        console.log("block chain id: ", block.chainid);
        console.log(
            "wormholeAdapter relayer: ",
            address(wormholeAdapter.wormholeRelayer())
        );

        uint256 cost = wormholeAdapter.bridgeCost(dstChainId);

        vm.deal(user, cost);

        vm.startPrank(user);
        xwell.approve(address(wormholeAdapter), mintAmount);
        wormholeAdapter.bridge{value: cost}(dstChainId, mintAmount, user);
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

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = chainIdToWormHoleId[
            sendingChainIdToReceivingChainId[block.chainid]
        ];

        bytes memory payload = abi.encode(user, mintAmount);
        bytes32 sender = wormholeAdapter.addressToBytes(
            address(wormholeAdapter)
        );
        bytes32 nonce = keccak256(abi.encode(payload, block.timestamp));

        vm.prank(address(wormholeAdapter.wormholeRelayer()));
        wormholeAdapter.receiveWormholeMessages(
            payload,
            new bytes[](0),
            sender,
            dstChainId,
            nonce
        );

        uint256 endingXWellBalance = xwell.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));

        assertEq(
            endingXWellBalance,
            startingXWellBalance + mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            endingXWellTotalSupply,
            startingXWellTotalSupply + mintAmount,
            "total xWELL supply incorrect"
        );
        assertTrue(wormholeAdapter.processedNonces(nonce), "nonce not used");
        assertEq(endingBuffer, startingBuffer - mintAmount, "buffer incorrect");

        return mintAmount;
    }
}

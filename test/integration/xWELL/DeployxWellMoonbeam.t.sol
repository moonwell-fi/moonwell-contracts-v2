// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {xwellDeployMoonbeam} from "@protocol/proposals/mips/mip-xwell/xwellDeployMoonbeam.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

import {Address} from "@utils/Address.sol";

contract DeployxWellLiveSystemMoonbeamTest is xwellDeployMoonbeam {
    using Address for address;

    /// @notice lockbox contract
    XERC20Lockbox public xerc20Lockbox;

    /// @notice original token contract
    ERC20 public well;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    uint16 public constant wormholeBaseChainid = uint16(baseWormholeChainId);

    function setUp() public {
        addresses = new Addresses();

        well = ERC20(addresses.getAddress("GOVTOKEN"));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        xerc20Lockbox = XERC20Lockbox(addresses.getAddress("xWELL_LOCKBOX"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        deal(address(well), user, startingWellAmount);
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

        vm.expectRevert("Initializable: contract is already initialized");
        wormholeAdapter.initialize(
            address(1),
            address(1),
            address(1),
            wormholeBaseChainid
        );
    }

    function testSetup() public view {
        address externalChainAddress = wormholeAdapter.targetAddress(
            wormholeBaseChainid
        );
        assertEq(
            externalChainAddress,
            address(wormholeAdapter),
            "incorrect target address config"
        );
        bytes32[] memory externalAddresses = wormholeAdapter.allTrustedSenders(
            wormholeBaseChainid
        );
        assertEq(externalAddresses.length, 1, "incorrect trusted senders");
        assertEq(
            externalAddresses[0],
            address(wormholeAdapter).toBytes(),
            "incorrect actual trusted senders"
        );
        assertTrue(
            wormholeAdapter.isTrustedSender(
                uint16(wormholeBaseChainid),
                address(wormholeAdapter)
            ),
            "self on moonbeam not trusted sender"
        );
    }

    function testMintViaLockbox(
        uint96 mintAmount
    ) public returns (uint256 minted) {
        uint256 startingUserBalance = well.balanceOf(user);
        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();

        mintAmount = uint96(minted = _bound(mintAmount, 1, startingWellAmount));

        vm.startPrank(user);
        well.approve(address(xerc20Lockbox), mintAmount);
        xerc20Lockbox.deposit(mintAmount);
        vm.stopPrank();

        uint256 endingUserBalance = well.balanceOf(user);
        uint256 endingXWellBalance = xwell.balanceOf(user);

        assertEq(
            endingUserBalance,
            startingUserBalance - mintAmount,
            "user well balance incorrect"
        );
        assertEq(
            endingXWellBalance,
            startingXWellBalance + mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply + mintAmount,
            "total xWELL supply incorrect"
        );
    }

    function testBurnViaLockbox(
        uint96 mintAmount
    ) public returns (uint256 burned) {
        mintAmount = uint96(burned = testMintViaLockbox(mintAmount));

        uint256 startingUserBalance = well.balanceOf(user);
        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();

        vm.startPrank(user);
        xwell.approve(address(xerc20Lockbox), mintAmount);
        xerc20Lockbox.withdraw(mintAmount);
        vm.stopPrank();

        uint256 endingUserBalance = well.balanceOf(user);
        uint256 endingXWellBalance = xwell.balanceOf(user);

        assertEq(
            endingUserBalance,
            startingUserBalance + mintAmount,
            "user well balance incorrect"
        );
        assertEq(
            endingXWellBalance,
            startingXWellBalance - mintAmount,
            "user xWELL balance incorrect"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply - mintAmount,
            "total xWELL supply incorrect"
        );
    }

    function testBridgeOutSuccess() public {
        uint256 mintAmount = testMintViaLockbox(uint96(startingWellAmount));

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = uint16(chainIdToWormHoleId[block.chainid]);
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

    function testBridgeInSuccess(uint256 mintAmount) public {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );

        uint256 startingWellBalance = well.balanceOf(user);
        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = uint16(chainIdToWormHoleId[block.chainid]);
        bytes memory payload = abi.encode(user, mintAmount);
        bytes32 sender = address(wormholeAdapter).toBytes();
        bytes32 nonce = keccak256(abi.encode(payload, block.timestamp));
        deal(address(well), addresses.getAddress("xWELL_LOCKBOX"), mintAmount);

        vm.prank(address(wormholeAdapter.wormholeRelayer()));
        wormholeAdapter.receiveWormholeMessages(
            payload,
            new bytes[](0),
            sender,
            dstChainId,
            nonce
        );

        uint256 endingWellBalance = well.balanceOf(user);
        uint256 endingXWellBalance = xwell.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));

        assertEq(
            endingXWellBalance,
            startingXWellBalance,
            "user xWELL balance incorrect, should not change"
        );
        assertEq(
            startingWellBalance + mintAmount,
            endingWellBalance,
            "user WELL balance incorrect, did not increase"
        );
        assertEq(
            endingXWellTotalSupply,
            startingXWellTotalSupply,
            "total xWELL supply incorrect, should not change"
        );

        assertTrue(wormholeAdapter.processedNonces(nonce), "nonce not used");
        assertEq(endingBuffer, startingBuffer - mintAmount, "buffer incorrect");
    }
}

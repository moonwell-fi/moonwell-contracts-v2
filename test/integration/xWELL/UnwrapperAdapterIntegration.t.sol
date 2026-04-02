// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {Address} from "@utils/Address.sol";

contract UnwrapperAdapterPostProposalTest is PostProposalCheck {
    using Address for address;
    using ChainIds for uint256;

    /// @notice lockbox contract
    XERC20Lockbox public xerc20Lockbox;

    /// @notice original token contract
    ERC20 public well;

    /// @notice logic contract, not initializable
    xWELL public xwell;

    /// @notice wormhole bridge adapter contract
    WormholeBridgeAdapter public wormholeAdapter;

    /// @notice mock wormhole core for processVAA tests
    MockWormholeCore public mockWormholeCore;

    /// @notice user address for testing
    address user = address(0x123);

    /// @notice amount of well to mint
    uint256 public constant startingWellAmount = 100_000 * 1e18;

    uint16 public constant wormholeBaseChainid = uint16(BASE_WORMHOLE_CHAIN_ID);

    function setUp() public override {
        super.setUp();

        well = ERC20(addresses.getAddress("GOVTOKEN"));
        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        xerc20Lockbox = XERC20Lockbox(addresses.getAddress("xWELL_LOCKBOX"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// Set up MockWormholeCore for processVAA tests.
        /// Override the wormhole address via vm.store since adapter is
        /// already V3-initialized after x48+x49 execution.
        mockWormholeCore = new MockWormholeCore();
        mockWormholeCore.setFee(0);
        mockWormholeCore.setChainId(uint16(MOONBEAM_WORMHOLE_CHAIN_ID));

        /// wormhole is at storage slot 156 in WormholeBridgeAdapter
        vm.store(
            address(wormholeAdapter),
            bytes32(uint256(156)),
            bytes32(uint256(uint160(address(mockWormholeCore))))
        );

        deal(address(well), user, startingWellAmount);
    }

    function testInitializeLogicContractFails() public {
        WormholeUnwrapperAdapter wormholeUnwrapperAdapter = WormholeUnwrapperAdapter(
                addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER")
            );

        vm.expectRevert();
        wormholeUnwrapperAdapter.initialize(
            address(1),
            address(1),
            address(1),
            new uint16[](0),
            new address[](0)
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
        uint256 burnAmount = testMintViaLockbox(uint96(startingWellAmount));

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = block.chainid.toBaseWormholeChainId();
        uint256 cost = wormholeAdapter.bridgeCost(dstChainId);

        vm.deal(user, cost);

        vm.startPrank(user);
        xwell.approve(address(wormholeAdapter), burnAmount);
        wormholeAdapter.bridge{value: cost}(dstChainId, burnAmount, user);
        vm.stopPrank();

        uint256 endingXWellBalance = xwell.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));

        assertEq(endingBuffer, startingBuffer + burnAmount, "buffer incorrect");
        assertEq(
            endingXWellBalance,
            startingXWellBalance - burnAmount,
            "user xWELL balance incorrect, should be unchanged"
        );
        assertEq(
            endingXWellTotalSupply + burnAmount,
            startingXWellTotalSupply,
            "total xWELL supply incorrect"
        );
    }

    /// @notice After x49, the adapter is WormholeUnwrapperAdapter with lockbox
    ///         restored. processVAA mints xWELL then unwraps to WELL via lockbox.
    function testBridgeInSuccess(uint256 mintAmount) public {
        mintAmount = _bound(
            mintAmount,
            1,
            xwell.buffer(address(wormholeAdapter))
        );
        deal(address(well), address(xerc20Lockbox), mintAmount);

        uint256 startingWellBalance = well.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));
        uint256 startingLockboxBuffer = xwell.buffer(address(xerc20Lockbox));

        /// Configure mock: emitter is the adapter on Base chain
        mockWormholeCore.setStorage(
            true,
            wormholeBaseChainid,
            address(wormholeAdapter).toBytes(),
            "",
            abi.encode(user, mintAmount, uint16(MOONBEAM_WORMHOLE_CHAIN_ID))
        );

        bytes memory vaaBytes = abi.encode(
            "bridge-in-vaa",
            mintAmount,
            block.timestamp
        );
        wormholeAdapter.processVAA(vaaBytes);

        uint256 endingWellBalance = well.balanceOf(user);
        uint256 endingXWellTotalSupply = xwell.totalSupply();
        uint256 endingBuffer = xwell.buffer(address(wormholeAdapter));
        uint256 endingLockboxBuffer = xwell.buffer(address(xerc20Lockbox));

        assertEq(
            endingWellBalance,
            startingWellBalance + mintAmount,
            "user WELL balance incorrect"
        );
        assertEq(
            endingXWellTotalSupply,
            startingXWellTotalSupply,
            "total xWELL supply changed"
        );
        assertTrue(
            wormholeAdapter.processedVAAHashes(keccak256(vaaBytes)),
            "VAA hash not processed"
        );
        assertEq(endingBuffer, startingBuffer - mintAmount, "buffer incorrect");
        assertEq(
            startingLockboxBuffer + mintAmount,
            endingLockboxBuffer,
            "lockbox buffer incorrect"
        );
    }
}

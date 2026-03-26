// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {XERC20Lockbox} from "@protocol/xWELL/XERC20Lockbox.sol";
import {BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {xwellDeployMoonbeam} from "@proposals/mips/mip-xwell/xwellDeployMoonbeam.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {ChainIds} from "@utils/ChainIds.sol";
import {Address} from "@utils/Address.sol";

contract DeployxWellMoonbeamTest is xwellDeployMoonbeam {
    using ChainIds for uint256;
    using Address for address;
    /// @notice all addresses
    Addresses public addresses;

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

    uint16 public constant wormholeBaseChainid = uint16(BASE_WORMHOLE_CHAIN_ID);

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
        uint256 mintAmount = testMintViaLockbox(uint96(startingWellAmount));

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = block.chainid.toBaseWormholeChainId();
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

        /// --- V3 upgrade + mock setup in scoped block to avoid stack-too-deep ---
        bytes memory vaaBytes;
        {
            uint16 currentWormholeChainId = uint16(MOONBEAM_WORMHOLE_CHAIN_ID);

            MockWormholeCore mockWormhole = new MockWormholeCore();
            mockWormhole.setChainId(currentWormholeChainId);

            ProxyAdmin pa = ProxyAdmin(
                addresses.getAddress("MOONBEAM_PROXY_ADMIN")
            );
            address newImpl = address(new WormholeUnwrapperAdapter());
            vm.prank(pa.owner());
            pa.upgradeAndCall(
                ITransparentUpgradeableProxy(address(wormholeAdapter)),
                newImpl,
                abi.encodeWithSelector(
                    WormholeBridgeAdapter.initializeV3.selector,
                    address(mockWormhole)
                )
            );

            address lockboxAddr = addresses.getAddress("xWELL_LOCKBOX");
            vm.prank(wormholeAdapter.owner());
            WormholeUnwrapperAdapter(address(wormholeAdapter)).setLockbox(
                lockboxAddr
            );

            deal(
                address(well),
                addresses.getAddress("xWELL_LOCKBOX"),
                mintAmount
            );

            mockWormhole.setStorage(
                true,
                uint16(BASE_WORMHOLE_CHAIN_ID),
                address(wormholeAdapter).toBytes(),
                "",
                abi.encode(user, mintAmount, currentWormholeChainId)
            );

            vaaBytes = abi.encode("bridge-in-vaa", mintAmount);
        }

        /// --- Bridge in via processVAA ---
        uint256 startingWellBalance = well.balanceOf(user);
        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        wormholeAdapter.processVAA(vaaBytes);

        assertEq(
            xwell.balanceOf(user),
            startingXWellBalance,
            "user xWELL balance incorrect, should not change"
        );
        assertEq(
            well.balanceOf(user),
            startingWellBalance + mintAmount,
            "user WELL balance incorrect, did not increase"
        );
        assertEq(
            xwell.totalSupply(),
            startingXWellTotalSupply,
            "total xWELL supply incorrect, should not change"
        );
        assertTrue(
            wormholeAdapter.processedVAAHashes(keccak256(vaaBytes)),
            "VAA hash not processed"
        );
        assertEq(
            xwell.buffer(address(wormholeAdapter)),
            startingBuffer - mintAmount,
            "buffer incorrect"
        );
    }
}

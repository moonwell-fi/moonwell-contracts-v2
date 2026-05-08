// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

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
import {MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract xWellIntegrationTest is Test {
    using ChainIds for uint256;
    using Address for address;

    /// @notice all addresses
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

        xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        wormholeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// Manually upgrade the adapter to V5 (Executor) for testing.
        /// CI runs this test with --fork-url base/optimism (single fork),
        /// so PostProposalCheck multi-fork pipeline is not available.
        _upgradeAdapterToV5();
    }

    /// @notice Deploy V5 impl and upgrade via proxy admin
    function _upgradeAdapterToV5() internal {
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");

        WormholeBridgeAdapter newImpl = new WormholeBridgeAdapter();

        /// Try to get executor addresses — they may or may not be in chain config
        address executorAddr;
        address quoterRouterAddr;
        address quoterAddr;
        try addresses.getAddress("WORMHOLE_EXECUTOR") returns (address a) {
            executorAddr = a;
        } catch {
            executorAddr = address(new MockExecutorQuoterRouter());
        }
        try addresses.getAddress("WORMHOLE_QUOTER_ROUTER") returns (address a) {
            quoterRouterAddr = a;
        } catch {
            quoterRouterAddr = address(new MockExecutorQuoterRouter());
        }
        try addresses.getAddress("WORMHOLE_QUOTER") returns (address a) {
            quoterAddr = a;
        } catch {
            quoterAddr = address(new MockExecutorQuoterRouter());
        }

        address proxyAdminOwner = ProxyAdmin(proxyAdmin).owner();
        vm.prank(proxyAdminOwner);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(proxy),
            address(newImpl),
            abi.encodeWithSignature(
                "initializeV5(address,address,address)",
                executorAddr,
                quoterRouterAddr,
                quoterAddr
            )
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

    /// @notice After V5 upgrade, validate Executor state
    function testExecutorStateAfterV5Upgrade() public view {
        assertTrue(
            address(wormholeAdapter.executor()) != address(0),
            "executor not set after V5"
        );
    }

    /// @notice Bridge out using the off-chain signed quote path.
    function testBridgeOutSuccess() public {
        uint256 mintAmount = testBridgeInSuccess(startingWellAmount);

        uint256 startingXWellBalance = xwell.balanceOf(user);
        uint256 startingXWellTotalSupply = xwell.totalSupply();
        uint256 startingBuffer = xwell.buffer(address(wormholeAdapter));

        uint16 dstChainId = block.chainid.toMoonbeamWormholeChainId();

        /// Etch MockExecutorQuoterRouter onto the real executor address
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
            hex"deadbeef"
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
        bytes memory vaaBytes;
        {
            MockWormholeCore mockWormhole = new MockWormholeCore();
            mockWormhole.setChainId(block.chainid.toWormholeChainId());

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
                abi.encode(
                    user,
                    mintAmount,
                    block.chainid.toWormholeChainId(),
                    address(wormholeAdapter)
                )
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

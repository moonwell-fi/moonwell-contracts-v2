// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;
import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import "@utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*

 Utility to deploy xWELL contract on any network

 to simulate:
     forge script script/DeployXWell.s.sol:DeployXWell -vvvv --rpc-url chainAlias

 to run:
    forge script script/DeployXWell.s.sol:DeployXWell -vvvv \ 
    --rpc-url chainAlias --broadcast --etherscan-api-key chainAlias --verify

*/
contract DeployXWell is Script, xWELLDeploy, Networks {
    using ChainIds for uint256;

    /// @notice the buffer cap for the xWELL token on all chains
    uint112 public constant bufferCap = 100_000_000 * 1e18;

    /// @notice the rate limit per second for the xWELL token on all chains
    /// heals at ~19m per day if buffer is fully replenished or depleted
    /// this limit is used for the wormhole bridge adapters
    uint128 public constant rateLimitPerSecond = 1158 * 1e18;

    /// @notice the duration of the pause for the xWELL token on all chains
    /// once the contract has been paused, in this period of time, it will automatically
    /// unpause if no action is taken.
    uint128 public constant pauseDuration = 10 days;

    /// @notice the expected nonce for the deployer address before deploying
    /// the xWELL token
    uint256 public constant expectedNonce = 473;

    function run() public {
        Addresses addresses = new Addresses();

        if (!addresses.isAddressSet("xWELL_LOGIC")) {
            vm.startBroadcast();

            address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
            address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
            address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
            address relayer = addresses.getAddress("WORMHOLE_BRIDGE_RELAYER");

            {
                (, address deployerAddress, ) = vm.readCallers();

                uint256 currentNonce = vm.getNonce(deployerAddress);
                uint256 increment = expectedNonce - currentNonce;

                for (uint256 i = 0; i < increment; i++) {
                    (bool success, ) = address(deployerAddress).call{value: 1}(
                        ""
                    );
                    success;
                }

                assertEq(
                    vm.getNonce(deployerAddress),
                    expectedNonce,
                    "incorrect nonce"
                );
            }

            (
                address xwellLogic,
                address xwellProxy,
                address wormholeAdapterLogic,
                address wormholeAdapter
            ) = deployWellSystem(proxyAdmin);

            /// Multichain Address Verification

            /// xWELL
            assertEq(
                xwellLogic,
                addresses.getAddress("xWELL_LOGIC", BASE_CHAIN_ID),
                "xWELL_LOGIC address is incorrect"
            );
            assertEq(
                xwellProxy,
                addresses.getAddress("xWELL_PROXY", BASE_CHAIN_ID),
                "xWELL_PROXY address is incorrect"
            );
            assertEq(
                xwellLogic,
                addresses.getAddress("xWELL_LOGIC", MOONBEAM_CHAIN_ID),
                "xWELL_LOGIC address is incorrect"
            );
            assertEq(
                xwellProxy,
                addresses.getAddress("xWELL_PROXY", MOONBEAM_CHAIN_ID),
                "xWELL_PROXY address is incorrect"
            );

            /// wormhole adapter
            assertEq(
                wormholeAdapterLogic,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                    BASE_CHAIN_ID
                ),
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC address is incorrect"
            );
            assertEq(
                wormholeAdapter,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    BASE_CHAIN_ID
                ),
                "WORMHOLE_BRIDGE_ADAPTER_PROXY address is incorrect"
            );
            assertEq(
                wormholeAdapterLogic,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                    MOONBEAM_CHAIN_ID
                ),
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC address is incorrect"
            );
            assertEq(
                wormholeAdapter,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    MOONBEAM_CHAIN_ID
                ),
                "WORMHOLE_BRIDGE_ADAPTER_PROXY address is incorrect"
            );

            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](1);

            limits[0].bridge = wormholeAdapter;
            limits[0].rateLimitPerSecond = rateLimitPerSecond;
            limits[0].bufferCap = bufferCap;

            /// xWELL and Wormhole Bridge Adapter Initialization

            initializeXWell(
                xwellProxy,
                "WELL",
                "WELL",
                temporalGov,
                limits,
                pauseDuration,
                pauseGuardian
            );

            /// trust all of the wormhole adapters on other chains
            address[] memory trustedSenders = new address[](
                networks.length - 1
            );
            uint16[] memory trustedChainIds = new uint16[](networks.length - 1);
            uint256 counter;

            /// iterate over all network configs
            for (uint256 i = 0; i < networks.length; i++) {
                /// skip the network we are on
                if (networks[i].chainId == block.chainid) {
                    continue;
                }

                /// trust the wormhole adapter on the other chain
                /// this is necessary for the wormhole bridge to work
                trustedSenders[counter] = addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    networks[i].chainId
                );
                /// trust the wormhole chainId for the given network
                trustedChainIds[counter] = networks[i].wormholeChainId;

                counter++;
            }

            for (uint256 i = 0; i < trustedSenders.length; i++) {
                console.log(
                    "trustedSender[%d]:\n %s\n %d",
                    i,
                    trustedSenders[i],
                    trustedChainIds[i]
                );
            }

            initializeWormholeAdapter(
                wormholeAdapter,
                xwellProxy,
                temporalGov,
                relayer,
                trustedChainIds,
                trustedSenders
            );
            vm.stopBroadcast();

            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                wormholeAdapter
            );
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                wormholeAdapterLogic
            );
            addresses.addAddress("xWELL_LOGIC", xwellLogic);
            addresses.addAddress("xWELL_PROXY", xwellProxy);

            addresses.printAddresses();
        }

        {
            address xWellProxy = addresses.getAddress("xWELL_PROXY");
            address wormholeAdapter = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY"
            );
            address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
            address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
            address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

            assertEq(
                xWELL(wormholeAdapter).owner(),
                temporalGov,
                "wormhole bridge adapter owner is incorrect"
            );
            assertEq(
                address(
                    WormholeBridgeAdapter(wormholeAdapter).wormholeRelayer()
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "wormhole bridge adapter relayer is incorrect"
            );
            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).gasLimit(),
                300_000,
                "wormhole bridge adapter gas limit is incorrect"
            );
            assertEq(
                xWELL(xWellProxy).owner(),
                temporalGov,
                "temporal gov address is incorrect"
            );
            assertEq(
                xWELL(xWellProxy).pendingOwner(),
                address(0),
                "pending owner address is incorrect"
            );

            /// ensure correct pause guardian
            assertEq(
                xWELL(xWellProxy).pauseGuardian(),
                pauseGuardian,
                "pause guardian address is incorrect"
            );
            /// ensure correct pause duration
            assertEq(
                xWELL(xWellProxy).pauseDuration(),
                pauseDuration,
                "pause duration is incorrect"
            );
            /// ensure correct rate limits
            assertEq(
                xWELL(xWellProxy).rateLimitPerSecond(wormholeAdapter),
                rateLimitPerSecond,
                "rateLimitPerSecond is incorrect"
            );
            /// ensure correct buffer cap
            assertEq(
                xWELL(xWellProxy).bufferCap(wormholeAdapter),
                bufferCap,
                "bufferCap is incorrect"
            );

            for (uint256 i = 0; i < networks.length; i++) {
                /// skip the network we are on
                if (networks[i].chainId == block.chainid) {
                    continue;
                }

                assertEq(
                    addresses.getAddress(
                        "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                        networks[i].chainId
                    ),
                    WormholeBridgeAdapter(wormholeAdapter).targetAddress(
                        networks[i].wormholeChainId
                    ),
                    "target address incorrect"
                );

                assertTrue(
                    WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                        networks[i].wormholeChainId,
                        wormholeAdapter
                    ),
                    "trusted sender not trusted"
                );
            }

            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).owner(),
                temporalGov,
                "wormhole adapter owner is incorrect"
            );

            /// ensure proxy admin has correct owner
            /// ensure correct wormhole adapter relayer
            /// ensure proxy contract owners are proxy admin
            assertEq(
                ProxyAdmin(proxyAdmin).owner(),
                temporalGov,
                "ProxyAdmin owner is incorrect"
            );

            validateProxy(
                vm,
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("xWELL_LOGIC"),
                proxyAdmin,
                "Optimism xWELL_PROXY validation"
            );

            validateProxy(
                vm,
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC"),
                proxyAdmin,
                "Optimism WORMHOLE_BRIDGE_ADAPTER_PROXY validation"
            );
        }
    }
}

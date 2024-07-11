//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";
import "@protocol/utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Configs} from "@proposals/Configs.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// how to run locally:
///
///     PRIMARY_FORK_ID=0      moonbeam
///     PRIMARY_FORK_ID=1      base
///     PRIMARY_FORK_ID=2      optimism
///
///   PRIMARY_FORK_ID=2 DO_DEPLOY=true DO_VALIDATE=true forge script src/proposals/mips/mip-xwell/xwellDeploy.sol:xwellDeploy -vvv
/// @dev do not use MIP as a base to fork off from
contract xwellDeploy is HybridProposal, xWELLDeploy, Networks {
    using ChainIds for uint256;

    /// @notice the name of the proposal
    string public constant override name = "MIP xWELL Token Creation";

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
    uint256 public constant expectedNonce = 387;

    /// @notice struct to hold the wormhole adapter config
    struct WormholeAdapterConfig {
        uint16 chainId;
        address wormholeAdapter;
    }

    function primaryForkId() public view override returns (uint256 forkId) {
        forkId = vm.envUint("PRIMARY_FORK_ID");

        require(forkId <= OPTIMISM_FORK_ID, "invalid primary fork id");
    }

    function deploy(Addresses addresses, address) public override {
        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ---------------- OPTIMISM NETWORK ----------------
        /// --------------------------------------------------
        /// --------------------------------------------------
        {
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
                    console.log(vm.getNonce(deployerAddress));
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

            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](1);

            limits[0].bridge = wormholeAdapter;
            limits[0].rateLimitPerSecond = rateLimitPerSecond;
            limits[0].bufferCap = bufferCap;

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

            initializeWormholeAdapter(
                wormholeAdapter,
                xwellProxy,
                temporalGov,
                relayer,
                trustedChainIds,
                trustedSenders
            );

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
        }
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    function build(Addresses addresses) public override {}

    /// no cross chain actions to run, so remove all code from this function
    /// @dev do not use MIP as a base to fork off of, it will not work
    function run(Addresses, address) public override(HybridProposal) {}

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        /// do validation for base network, then do validation for moonbeam network
        //// ensure chainId is correct and non zero
        /// ensure correct owner

        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ------------------ BASE NETWORK ------------------
        /// --------------------------------------------------
        /// --------------------------------------------------
        {
            address basexWellProxy = addresses.getAddress("xWELL_PROXY");
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
                xWELL(basexWellProxy).owner(),
                temporalGov,
                "temporal gov address is incorrect"
            );
            assertEq(
                xWELL(basexWellProxy).pendingOwner(),
                address(0),
                "pending owner address is incorrect"
            );

            /// ensure correct pause guardian
            assertEq(
                xWELL(basexWellProxy).pauseGuardian(),
                pauseGuardian,
                "pause guardian address is incorrect"
            );
            /// ensure correct pause duration
            assertEq(
                xWELL(basexWellProxy).pauseDuration(),
                pauseDuration,
                "pause duration is incorrect"
            );
            /// ensure correct rate limits
            assertEq(
                xWELL(basexWellProxy).rateLimitPerSecond(wormholeAdapter),
                rateLimitPerSecond,
                "rateLimitPerSecond is incorrect"
            );
            /// ensure correct buffer cap
            assertEq(
                xWELL(basexWellProxy).bufferCap(wormholeAdapter),
                bufferCap,
                "bufferCap is incorrect"
            );

            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).targetAddress(
                    block.chainid.toMoonbeamWormholeChainId()
                ),
                wormholeAdapter,
                "moonbeam target address incorrect"
            );
            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).targetAddress(
                    block.chainid.toBaseWormholeChainId()
                ),
                wormholeAdapter,
                "base target address incorrect"
            );

            assertTrue(
                WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                    block.chainid.toMoonbeamWormholeChainId(),
                    wormholeAdapter
                ),
                "trusted sender not trusted"
            );
            assertTrue(
                WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                    block.chainid.toBaseWormholeChainId(),
                    wormholeAdapter
                ),
                "trusted sender not trusted"
            );
            /// ensure correct wormhole adapter logic
            /// ensure correct wormhole adapter owner
            assertEq(
                WormholeBridgeAdapter(wormholeAdapter).owner(),
                temporalGov,
                "wormhole adapter owner is incorrect"
            );
            /// ensure correct wormhole adapter relayer
            /// ensure correct wormhole adapter wormhole id
            /// ensure proxy admin has correct owner
            /// ensure proxy contract owners are proxy admin
            assertEq(
                ProxyAdmin(proxyAdmin).owner(),
                temporalGov,
                "ProxyAdmin owner is incorrect"
            );
            assertEq(
                ProxyAdmin(proxyAdmin).getProxyAdmin(
                    ITransparentUpgradeableProxy(basexWellProxy)
                ),
                proxyAdmin,
                "Admin is incorrect basexWellProxy"
            );
            assertEq(
                ProxyAdmin(proxyAdmin).getProxyAdmin(
                    ITransparentUpgradeableProxy(wormholeAdapter)
                ),
                proxyAdmin,
                "Admin is incorrect wormholeAdapter"
            );
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, ETHEREUM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";

/*

 Deploy xWELL and stkWELL to Ethereum mainnet

 This script handles the deployment of:
 - ProxyAdmin (if not exists)
 - xWELL token with Wormhole bridge adapter
 - Ecosystem Reserve
 - stkWELL (Staked WELL)

 Libraries (RateLimitMidpointCommonLibrary, Math) are automatically linked during deployment.

 to simulate:
     forge script script/DeployXWellEthereum.s.sol:DeployXWellEthereum -vvvv --rpc-url ethereum

 to run:
    forge script script/DeployXWellEthereum.s.sol:DeployXWellEthereum -vvvv \
    --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract DeployXWellEthereum is Script, xWELLDeploy {
    /// @notice Constants for Ethereum xWELL deployment
    uint112 public constant ETH_XWELL_BUFFER_CAP = 100_000_000 * 1e18;
    uint128 public constant ETH_XWELL_RATE_LIMIT_PER_SECOND = 1158 * 1e18; // ~19m per day
    uint128 public constant ETH_XWELL_PAUSE_DURATION = 10 days;

    /// @notice Constants for Ethereum stkWELL deployment
    uint256 public constant ETH_STKWELL_COOLDOWN_SECONDS = 604800; // onchain value on base
    uint256 public constant ETH_STKWELL_UNSTAKE_WINDOW = 172800; // onchain value on base
    uint128 public constant ETH_STKWELL_DISTRIBUTION_END = 4864764777; // onchain value on base

    /// @notice Deploy xWELL system with nonce management to match Base address
    /// @dev Burns nonces until we reach the correct nonce to deploy xWELL_PROXY
    ///      at the same address as on Base
    /// @param addresses The addresses contract for loading Base xWELL_PROXY address
    /// @param proxyAdmin The proxy admin address to use
    /// @return xwellLogic The xWELL logic contract address
    /// @return xwellProxy The xWELL proxy address (will match Base)
    /// @return wormholeAdapterLogic The wormhole adapter logic address
    /// @return wormholeAdapter The wormhole adapter proxy address
    function _deployXWellSystemWithNonceMatching(
        Addresses addresses,
        address proxyAdmin
    )
        private
        returns (
            address xwellLogic,
            address xwellProxy,
            address wormholeAdapterLogic,
            address wormholeAdapter
        )
    {
        // Load target xWELL_PROXY address from Base
        address targetXwellProxy = addresses.getAddress(
            "xWELL_PROXY",
            BASE_CHAIN_ID
        );

        // Get deployer address from private key
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        console.log("Deployer address:", deployer);

        uint256 currentNonce = vm.getNonce(deployer);

        // Calculate which nonce will produce the xWELL_PROXY
        // deployWellSystem deploys in order:
        //   nonce N:   xwellLogic
        //   nonce N+1: wormholeAdapterLogic
        //   nonce N+2: xwellProxy (this is the one we need to match)
        //   nonce N+3: wormholeAdapter
        // So we need to find the starting nonce N such that N+2 produces targetXwellProxy

        // Search for the target nonce (try nonces from current up to a reasonable max)
        uint256 targetStartNonce = type(uint256).max;
        for (uint256 n = currentNonce; n < currentNonce + 1000; n++) {
            address predicted = vm.computeCreateAddress(deployer, n + 2);
            if (predicted == targetXwellProxy) {
                targetStartNonce = n;
                break;
            }
        }

        require(
            targetStartNonce != type(uint256).max,
            "Could not find nonce that produces target xWELL_PROXY address within search range"
        );

        console.log("Target xWELL_PROXY (from Base):", targetXwellProxy);

        // Burn nonces if needed
        if (currentNonce < targetStartNonce) {
            uint256 noncesToBurn = targetStartNonce - currentNonce;

            for (uint256 i = 0; i < noncesToBurn; i++) {
                // Self-transfer with 0 value - cheapest tx at 21000 gas
                (bool success, ) = deployer.call{value: 0}("");
                require(success, "Nonce burn failed");
            }

            console.log("Nonces burned. New nonce:", vm.getNonce(deployer));
        }

        // Final verification before deployment
        uint256 finalNonce = vm.getNonce(deployer);
        address predictedXwellProxy = vm.computeCreateAddress(
            deployer,
            finalNonce + 2
        );
        require(
            predictedXwellProxy == targetXwellProxy,
            "Predicted xWELL_PROXY address does not match Base"
        );

        console.log(
            "Verified: xWELL_PROXY will deploy to:",
            predictedXwellProxy
        );

        // Now deploy the xWELL system
        (
            xwellLogic,
            xwellProxy,
            wormholeAdapterLogic,
            wormholeAdapter
        ) = deployWellSystem(proxyAdmin);

        // Final sanity check
        require(
            xwellProxy == targetXwellProxy,
            "Deployed xWELL_PROXY address does not match Base"
        );
    }

    function run() public {
        Addresses addresses = new Addresses();

        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "This script must be run on Ethereum mainnet"
        );

        vm.startBroadcast();

        address proxyAdmin;
        address xwellProxy;
        address ecosystemReserveProxy;
        address stkWellProxy;
        address deployer = addresses.getAddress("MOONWELL_DEPLOYER");

        // 1. Deploy or get ProxyAdmin
        if (!addresses.isAddressSet("PROXY_ADMIN")) {
            proxyAdmin = address(new ProxyAdmin());
            addresses.addAddress("PROXY_ADMIN", proxyAdmin);
            console.log("Deployed ProxyAdmin:", proxyAdmin);
        } else {
            proxyAdmin = addresses.getAddress("PROXY_ADMIN");
            console.log("Using existing ProxyAdmin:", proxyAdmin);
        }

        // 2. Deploy xWELL system if not exists
        if (!addresses.isAddressSet("xWELL_PROXY")) {
            // TODO: use grantPauseGuardian in the proposal script to set new PAUSE_GUARDIAN
            address pauseGuardian = addresses.getAddress(
                "PAUSE_GUARDIAN_DEPRECATED"
            );

            (
                address xwellLogic,
                address _xwellProxy,
                address wormholeAdapterLogic,
                address wormholeAdapter
            ) = _deployXWellSystemWithNonceMatching(addresses, proxyAdmin);

            xwellProxy = _xwellProxy;

            // Set up rate limits for xWELL
            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](1);

            limits[0].bridge = wormholeAdapter;
            limits[0].rateLimitPerSecond = ETH_XWELL_RATE_LIMIT_PER_SECOND;
            limits[0].bufferCap = ETH_XWELL_BUFFER_CAP;

            initializeXWell(
                xwellProxy,
                "WELL",
                "WELL",
                deployer, // contract owner
                limits,
                ETH_XWELL_PAUSE_DURATION,
                pauseGuardian
            );

            // Trust Moonbeam/Base/Optimism wormhole adapters
            address[] memory trustedSenders = new address[](3);
            uint16[] memory trustedChainIds = new uint16[](3);

            trustedSenders[0] = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                MOONBEAM_CHAIN_ID
            );
            trustedChainIds[0] = MOONBEAM_WORMHOLE_CHAIN_ID;

            trustedSenders[1] = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                BASE_CHAIN_ID
            );
            trustedChainIds[1] = BASE_WORMHOLE_CHAIN_ID;

            trustedSenders[2] = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                OPTIMISM_CHAIN_ID
            );
            trustedChainIds[2] = OPTIMISM_WORMHOLE_CHAIN_ID;

            address wormholeRelayer = addresses.getAddress(
                "WORMHOLE_BRIDGE_RELAYER_PROXY"
            );
            initializeWormholeAdapter(
                wormholeAdapter,
                xwellProxy,
                deployer, // contract owner
                wormholeRelayer,
                trustedChainIds,
                trustedSenders
            );

            // Save xWELL addresses
            addresses.addAddress("xWELL_LOGIC", xwellLogic);
            addresses.addAddress("xWELL_PROXY", xwellProxy);
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                wormholeAdapterLogic
            );
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                wormholeAdapter
            );

            console.log("Deployed xWELL system:");
            console.log("  xWELL Proxy:", xwellProxy);
            console.log("  xWELL Logic:", xwellLogic);
            console.log("  Wormhole Adapter Proxy:", wormholeAdapter);
            console.log("  Wormhole Adapter Logic:", wormholeAdapterLogic);
        } else {
            xwellProxy = addresses.getAddress("xWELL_PROXY");
            console.log("Using existing xWELL:", xwellProxy);
        }

        // 3. Deploy Ecosystem Reserve if not exists
        if (!addresses.isAddressSet("ECOSYSTEM_RESERVE_PROXY")) {
            address ecosystemReserveImplementation = deployCode(
                "EcosystemReserve.sol:EcosystemReserve"
            );

            address ecosystemReserveController = deployCode(
                "EcosystemReserveController.sol:EcosystemReserveController"
            );

            ecosystemReserveProxy = address(
                new TransparentUpgradeableProxy(
                    ecosystemReserveImplementation,
                    proxyAdmin,
                    abi.encodeWithSignature(
                        "initialize(address)",
                        ecosystemReserveController
                    )
                )
            );

            addresses.addAddress(
                "ECOSYSTEM_RESERVE_IMPL",
                ecosystemReserveImplementation
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_CONTROLLER",
                ecosystemReserveController
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_PROXY",
                ecosystemReserveProxy
            );

            console.log("Deployed Ecosystem Reserve:");
            console.log("  Proxy:", ecosystemReserveProxy);
            console.log("  Implementation:", ecosystemReserveImplementation);
            console.log("  Controller:", ecosystemReserveController);
        } else {
            ecosystemReserveProxy = addresses.getAddress(
                "ECOSYSTEM_RESERVE_PROXY"
            );
            console.log(
                "Using existing Ecosystem Reserve:",
                ecosystemReserveProxy
            );
        }

        // 4. Deploy StakedWell (stkWELL) if not exists
        if (!addresses.isAddressSet("STK_GOVTOKEN_PROXY")) {
            address stkWellImplementation = deployCode(
                "StakedWell.sol:StakedWell"
            );

            // Generate init calldata for stkWELL
            bytes memory stkWellInitData = abi.encodeWithSignature(
                "initialize(address,address,uint256,uint256,address,address,uint128,address)",
                xwellProxy, // stakedToken (users stake xWELL)
                xwellProxy, // rewardToken (rewards paid in xWELL)
                ETH_STKWELL_COOLDOWN_SECONDS,
                ETH_STKWELL_UNSTAKE_WINDOW,
                ecosystemReserveProxy, // rewardsVault
                deployer, // emissionManager (TODO: use deployer in the proposal script to set the emission manager)
                ETH_STKWELL_DISTRIBUTION_END - block.timestamp, // dynamically calculate duration to match onchain value on base
                address(0) // governance (no transfer hook needed)
            );

            // Deploy stkWELL proxy
            stkWellProxy = address(
                new TransparentUpgradeableProxy(
                    stkWellImplementation,
                    proxyAdmin,
                    stkWellInitData
                )
            );

            addresses.addAddress("STK_GOVTOKEN_IMPL", stkWellImplementation);
            addresses.addAddress("STK_GOVTOKEN_PROXY", stkWellProxy);

            console.log("Deployed stkWELL:");
            console.log("  Proxy:", stkWellProxy);
            console.log("  Implementation:", stkWellImplementation);
        } else {
            stkWellProxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
            console.log("Using existing stkWELL:", stkWellProxy);
        }

        vm.stopBroadcast();

        console.log("\n=== Ethereum Deployment Complete ===");
        addresses.printAddresses();

        // Run validation
        _validateDeployment(addresses);
    }

    function _validateDeployment(Addresses addresses) internal view {
        address xwellProxy = addresses.getAddress("xWELL_PROXY");
        address wormholeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address deployer = addresses.getAddress("MOONWELL_DEPLOYER");
        address stkWellProxy = addresses.getAddress("STK_GOVTOKEN_PROXY");
        address ecosystemReserveProxy = addresses.getAddress(
            "ECOSYSTEM_RESERVE_PROXY"
        );

        console.log("\n=== Running Validation ===");

        // Validate xWELL and Wormhole Adapter ownership
        require(
            WormholeBridgeAdapter(wormholeAdapter).owner() == deployer,
            "Ethereum: wormhole bridge adapter owner is incorrect"
        );

        require(
            address(WormholeBridgeAdapter(wormholeAdapter).wormholeRelayer()) ==
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"),
            "Ethereum: wormhole bridge adapter relayer is incorrect"
        );

        require(
            WormholeBridgeAdapter(wormholeAdapter).gasLimit() == 300_000,
            "Ethereum: wormhole bridge adapter gas limit is incorrect"
        );

        require(
            xWELL(xwellProxy).owner() == deployer,
            "Ethereum: xWELL owner is incorrect (should be PROXY_ADMIN)"
        );

        require(
            xWELL(xwellProxy).pendingOwner() == address(0),
            "Ethereum: xWELL pending owner should be address(0)"
        );

        // Validate pause guardian
        require(
            xWELL(xwellProxy).pauseGuardian() ==
                addresses.getAddress("PAUSE_GUARDIAN_DEPRECATED"),
            "Ethereum: pause guardian is incorrect (should be PAUSE_GUARDIAN)"
        );

        // Validate pause duration
        require(
            xWELL(xwellProxy).pauseDuration() == ETH_XWELL_PAUSE_DURATION,
            "Ethereum: pause duration is incorrect"
        );

        // Validate rate limits
        require(
            xWELL(xwellProxy).rateLimitPerSecond(wormholeAdapter) ==
                ETH_XWELL_RATE_LIMIT_PER_SECOND,
            "Ethereum: rateLimitPerSecond is incorrect"
        );

        // Validate buffer cap
        require(
            xWELL(xwellProxy).bufferCap(wormholeAdapter) ==
                ETH_XWELL_BUFFER_CAP,
            "Ethereum: bufferCap is incorrect"
        );

        // Validate trusted senders
        address moonbeamWormholeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            MOONBEAM_CHAIN_ID
        );
        address baseWormholeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            BASE_CHAIN_ID
        );
        address optimismWormholeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            OPTIMISM_CHAIN_ID
        );

        require(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamWormholeAdapter
            ),
            "Ethereum: Moonbeam wormhole adapter not trusted"
        );

        require(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                baseWormholeAdapter
            ),
            "Ethereum: Base wormhole adapter not trusted"
        );

        require(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                optimismWormholeAdapter
            ),
            "Ethereum: Optimism wormhole adapter not trusted"
        );

        // Validate proxy admin
        validateProxy(
            vm,
            xwellProxy,
            addresses.getAddress("xWELL_LOGIC"),
            proxyAdmin,
            "Ethereum xWELL_PROXY"
        );

        validateProxy(
            vm,
            wormholeAdapter,
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC"),
            proxyAdmin,
            "Ethereum WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        // Validate stkWELL deployment
        require(
            address(IStakedWell(stkWellProxy).STAKED_TOKEN()) == xwellProxy,
            "Ethereum: stkWELL staked token should be xWELL"
        );

        require(
            address(IStakedWell(stkWellProxy).REWARD_TOKEN()) == xwellProxy,
            "Ethereum: stkWELL reward token should be xWELL"
        );

        require(
            IStakedWell(stkWellProxy).COOLDOWN_SECONDS() ==
                ETH_STKWELL_COOLDOWN_SECONDS,
            "Ethereum: stkWELL cooldown seconds is incorrect"
        );

        require(
            IStakedWell(stkWellProxy).UNSTAKE_WINDOW() ==
                ETH_STKWELL_UNSTAKE_WINDOW,
            "Ethereum: stkWELL unstake window is incorrect"
        );

        require(
            address(IStakedWell(stkWellProxy).REWARDS_VAULT()) ==
                ecosystemReserveProxy,
            "Ethereum: stkWELL rewards vault should be ecosystem reserve"
        );

        require(
            IStakedWell(stkWellProxy).EMISSION_MANAGER() == deployer,
            "Ethereum: stkWELL emission manager should be deployer"
        );

        // Validate proxy admin for stkWELL and ecosystem reserve
        validateProxy(
            vm,
            stkWellProxy,
            addresses.getAddress("STK_GOVTOKEN_IMPL"),
            proxyAdmin,
            "Ethereum STK_GOVTOKEN_PROXY"
        );

        validateProxy(
            vm,
            ecosystemReserveProxy,
            addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"),
            proxyAdmin,
            "Ethereum ECOSYSTEM_RESERVE_PROXY"
        );

        console.log("=== Validation Passed ===\n");
    }
}

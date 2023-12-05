pragma solidity 0.8.19;

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Recovery} from "@protocol/Recovery.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

/*
 to simulate:
    forge script script/xWellDeployScript.s.sol:xWellDeployScript \
     \ -vvvvv --rpc-url base --with-gas-price 500000
 to run:
    forge script script/xWellDeployScript.s.sol:xWellDeployScript \
     \ -vvvvv --rpc-url base --with-gas-price 500000 --broadcast
*/
/// TODO make this a MIP
contract xWellDeployBase is Script, Test, xWELLDeploy, ChainIds {
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 internal PRIVATE_KEY;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(
            vm.envOr("ETH_PRIVATE_KEY", bytes32(type(uint256).max))
        );

        addresses = new Addresses();
    }
}

contract xWellDeployScript is Script /*Test,*/, xWellDeployBase {
    uint112 public constant bufferCap = 100_000_000 * 1e18;
    uint128 public constant rateLimitPerSecond = 100_000_000 * 1e18;
    uint128 public constant pauseDuration = 10 days;

    function run()
        public
        returns (
            address xwellLogic,
            address xwellProxy,
            address proxyAdmin,
            address wormholeAdapterLogic,
            address wormholeAdapter
        )
    {
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        address temporalGov = addresses.getAddress("TEMPORAL_GOVERNOR");
        address adapter = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER");
        address relayer = addresses.getAddress("WORMHOLE_BRIDGE_RELAYER");

        vm.startBroadcast(PRIVATE_KEY);

        (
            xwellLogic,
            xwellProxy,
            proxyAdmin,
            wormholeAdapterLogic,
            wormholeAdapter
        ) = deployBaseSystem();

        MintLimits.RateLimitMidPointInfo[]
            memory limits = new MintLimits.RateLimitMidPointInfo[](1);

        limits[0].bridge = wormholeAdapter;
        limits[0].rateLimitPerSecond = rateLimitPerSecond;
        limits[0].bufferCap = bufferCap;

        /// TODO this is for the Moonbeam network
        // limits[1].bridge = lockbox;
        // limits[1].rateLimitPerSecond = rateLimitPerSecond;
        // limits[1].bufferCap = bufferCap;

        initializeXWell(
            xwellProxy,
            "WELL Token",
            "xWELL",
            temporalGov,
            limits,
            pauseDuration,
            pauseGuardian
        );

        initializeWormholeAdapter(
            wormholeAdapter,
            xwellProxy,
            temporalGov,
            relayer,
            uint16(
                chainIdToWormHoleId[
                    sendingChainIdToReceivingChainId[block.chainid]
                ]
            )
        );

        ProxyAdmin(proxyAdmin).transferOwnership(temporalGov);

        vm.stopBroadcast();

        // assertEq(, 0, "");
        //// ensure chainId is correct and non zero
        /// ensure correct owner
        assertEq(
            xWELL(xwellProxy).owner(),
            temporalGov,
            "temporal gov address is incorrect"
        );
        assertEq(
            xWELL(xwellProxy).pendingOwner(),
            address(0),
            "pending owner address is incorrect"
        );

        /// ensure correct pause guardian
        assertEq(
            xWELL(xwellProxy).pauseGuardian(),
            pauseGuardian,
            "pause guardian address is incorrect"
        );
        /// ensure correct pause duration
        assertEq(
            xWELL(xwellProxy).pauseDuration(),
            pauseDuration,
            "pause duration is incorrect"
        );
        /// ensure correct rate limits
        assertEq(
            xWELL(xwellProxy).rateLimitPerSecond(wormholeAdapter),
            rateLimitPerSecond,
            "rateLimitPerSecond is incorrect"
        );
        assertEq(
            xWELL(xwellProxy).rateLimitPerSecond(wormholeAdapter),
            rateLimitPerSecond,
            "rateLimitPerSecond is incorrect"
        );
        // assertEq(
        //     xWELL(xwellProxy).midPoint(wormholeAdapter),
        //     bufferCap / 2,
        //     "midpoint is incorrect"
        // );
        /// ensure correct buffer cap
        assertEq(
            xWELL(xwellProxy).bufferCap(wormholeAdapter),
            bufferCap,
            "bufferCap is incorrect"
        );
        assertTrue(
            WormholeBridgeAdapter(wormholeAdapter).isTrustedSender(
                uint16(
                    chainIdToWormHoleId[
                        sendingChainIdToReceivingChainId[block.chainid]
                    ]
                ),
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
            ProxyAdmin(proxyAdmin).getProxyAdmin(ITransparentUpgradeableProxy(xwellProxy)),
            proxyAdmin,
            "Admin is incorrect xwellproxy"
        );
        assertEq(
            ProxyAdmin(proxyAdmin).getProxyAdmin(ITransparentUpgradeableProxy(wormholeAdapter)),
            proxyAdmin,
            "Admin is incorrect wormholeAdapter"
        );
    }
}

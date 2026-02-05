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

 Emergency upgrade of xWELL and WormholeBridgeAdapter on Ethereum mainnet

 This script upgrades the xWELL and WormholeBridgeAdapter contracts to the new logic contracts which transfer ownership
 to the deployer address (previously set as the PROXY_ADMIN).

 to simulate:
     forge script script/EmergencyXWellUpgrade.s.sol:EmergencyXWellUpgrade -vvvv --rpc-url ethereum

 to run:
    forge script script/DeployXWellEthereum.s.sol:DeployXWellEthereum -vvvv \
    --rpc-url ethereum --broadcast --etherscan-api-key ethereum --verify

*/
contract EmergencyXWellUpgrade is Script {
    function run() public {
        Addresses addresses = new Addresses();

        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "This script must be run on Ethereum mainnet"
        );

        ProxyAdmin proxyAdmin = ProxyAdmin(addresses.getAddress("PROXY_ADMIN"));

        // 0. Transfer ownership from the MOONWELL DEPLOYER 1 to the real deployer of xwell
        address oldDeployer = vm.addr(vm.envUint("OLD_DEPLOYER_PRIVATE_KEY"));
        address deployer = vm.addr(vm.envUint("DEPLOYER_PRIVATE_KEY"));

        vm.startBroadcast(oldDeployer);
        proxyAdmin.transferOwnership(deployer);
        vm.stopBroadcast();

        vm.startBroadcast(deployer);

        // Save old logic addresses with _DEPRECATED suffix
        address oldXwellLogic = addresses.getAddress("xWELL_LOGIC");
        address oldWormholeAdapterLogic = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC"
        );

        addresses.addAddress("xWELL_LOGIC_DEPRECATED", oldXwellLogic);
        addresses.addAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC_DEPRECATED",
            oldWormholeAdapterLogic
        );

        // 1. Deploy new xWELL logic contract
        address newXwellLogic = address(new xWELL());

        // 2. Deploy new WormholeBridgeAdapter logic contract
        address newWormholeAdapterLogic = address(new WormholeBridgeAdapter());

        // Save new logic addresses
        addresses.changeAddress("xWELL_LOGIC", newXwellLogic, true);
        addresses.changeAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
            newWormholeAdapterLogic,
            true
        );

        // 3. Upgrade xWELL proxy to new logic contract
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(addresses.getAddress("xWELL_PROXY")),
            newXwellLogic,
            abi.encodeWithSignature("initializeV2(address)", deployer)
        );

        // 4. Upgrade WormholeBridgeAdapter proxy to new logic contract
        proxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            newWormholeAdapterLogic,
            abi.encodeWithSignature("initializeV2(address)", deployer)
        );

        vm.stopBroadcast();

        addresses.printAddresses();

        // Run validation
        _validateDeployment(addresses, proxyAdmin, deployer);
    }

    function _validateDeployment(
        Addresses addresses,
        ProxyAdmin proxyAdmin,
        address deployer
    ) internal view {
        address xwellProxy = addresses.getAddress("xWELL_PROXY");
        address wormholeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address newXwellLogic = addresses.getAddress("xWELL_LOGIC");
        address newWormholeAdapterLogic = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC"
        );
        address oldXwellLogic = addresses.getAddress("xWELL_LOGIC_DEPRECATED");
        address oldWormholeAdapterLogic = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC_DEPRECATED"
        );

        console.log("\n=== Running Validation ===");

        // Validate proxy admin ownership transferred to deployer
        require(
            proxyAdmin.owner() == deployer,
            "Ethereum: proxy admin owner is incorrect"
        );
        console.log("proxy admin owner is deployer:", deployer);

        // Validate new logic addresses are different from old ones
        require(
            newXwellLogic != oldXwellLogic,
            "Ethereum: new xWELL logic should be different from old logic"
        );
        console.log(
            "xWELL logic upgraded from",
            oldXwellLogic,
            "to",
            newXwellLogic
        );

        require(
            newWormholeAdapterLogic != oldWormholeAdapterLogic,
            "Ethereum: new WormholeBridgeAdapter logic should be different from old logic"
        );
        console.log(
            "WormholeBridgeAdapter logic upgraded from",
            oldWormholeAdapterLogic,
            "to",
            newWormholeAdapterLogic
        );

        // Validate xWELL and Wormhole Adapter ownership transferred to deployer
        require(
            WormholeBridgeAdapter(wormholeAdapterProxy).owner() == deployer,
            "Ethereum: wormhole bridge adapter owner is incorrect"
        );
        console.log("WormholeBridgeAdapter owner is deployer:", deployer);

        require(
            xWELL(xwellProxy).owner() == deployer,
            "Ethereum: xWELL owner is incorrect"
        );
        console.log("xWELL owner is deployer:", deployer);

        // Validate proxy implementations point to new logic
        validateProxy(
            vm,
            xwellProxy,
            newXwellLogic,
            address(proxyAdmin),
            "Ethereum xWELL_PROXY"
        );

        validateProxy(
            vm,
            wormholeAdapterProxy,
            newWormholeAdapterLogic,
            address(proxyAdmin),
            "Ethereum WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        // Validate basic functionality still works
        require(
            xWELL(xwellProxy).decimals() == 18,
            "Ethereum: xWELL decimals should be 18"
        );

        require(
            bytes(xWELL(xwellProxy).name()).length > 0,
            "Ethereum: xWELL name should not be empty"
        );

        require(
            bytes(xWELL(xwellProxy).symbol()).length > 0,
            "Ethereum: xWELL symbol should not be empty"
        );

        console.log("=== Validation Passed ===\n");
    }
}

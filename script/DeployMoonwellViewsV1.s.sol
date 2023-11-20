// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV1} from "@protocol/views/MoonwellViewsV1.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/*
How to use:
1. run:
forge script proposals/DeployMoonwellViewsV1.s.sol:DeployMoonwellViewsV1 \
    -vvvv \
    --rpc-url moonbeam \
    --broadcast --etherscan-api-key moonbeam --verify
Remove `--broadcast --etherscan-api-key moonbeam --verify` if you want to try locally
 first, without paying any gas.
*/

contract DeployMoonwellViewsV1 is Script, Test {
    uint256 public PRIVATE_KEY;

    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();

        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = vm.envOr(
            "MOONWELL_DEPLOY_PK",
            77814517325470205911140941194401928579557062014761831930645393041380819009408
        );
    }

    function run() public {
        address deployerAddress = vm.addr(PRIVATE_KEY);

        console.log("deployer address: %s", deployerAddress);

        vm.startBroadcast(PRIVATE_KEY);

        address unitroller = addresses.getAddress("UNITROLLER");
        address tokenSaleDistributor = addresses.getAddress("TOKENSALE");
        address safetyModule = addresses.getAddress("STWELL");
        address governanceToken = addresses.getAddress("WELL");
        address nativeMarket = addresses.getAddress("MGLIMMER");
        address governanceTokenLP = addresses.getAddress("WELL_LP");

        MoonwellViewsV1 viewsContract = new MoonwellViewsV1();

        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address,address,address,address,address)",
            unitroller,
            tokenSaleDistributor,
            safetyModule,
            governanceToken,
            nativeMarket,
            governanceTokenLP
        );

        ProxyAdmin proxyAdmin = new ProxyAdmin();

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(viewsContract),
            address(proxyAdmin),
            initdata
        );

        console.log("viewsContract address: %s", address(viewsContract));
        console.log("proxy admin address: %s", address(proxyAdmin));
        console.log("proxy address: %s", address(proxy));

        // addresses.addAddress("VIEWS_IMPL", address(viewsContract));
        // addresses.addAddress("VIEWS_PROXY", address(proxy));

        vm.stopBroadcast();
    }
}

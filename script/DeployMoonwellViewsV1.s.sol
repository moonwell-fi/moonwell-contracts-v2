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
to run:
forge script script/DeployMoonwellViewsV1.s.sol:DeployMoonwellViewsV1 -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
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
        vm.startBroadcast(PRIVATE_KEY);

        address unitroller = addresses.getAddress("UNITROLLER");
        address tokenSaleDistributor = addresses.getAddress("TOKENSALE");
        address safetyModule = addresses.getAddress("STWELL");
        address governanceToken = addresses.getAddress("GOVTOKEN");
        address nativeMarket = addresses.getAddress("mGLIMMER");
        address governanceTokenLP = addresses.getAddress("GOVTOKEN_LP);

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

        new TransparentUpgradeableProxy(
            address(viewsContract),
            address(proxyAdmin),
            initdata
        );

        vm.stopBroadcast();
    }
}

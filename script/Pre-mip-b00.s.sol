// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {MoonwellViewsV2} from "@protocol/views/MoonwellViewsV2.sol";
import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";

import {ChainlinkCompositeOracle} from "@protocol/Oracles/ChainlinkCompositeOracle.sol";

/*
to run:
forge script script/PreMip00Script.s.sol:PreMip00Script -vvvv --rpc-url {rpc}  --broadcast --etherscan-api-key {key}
*/
// Script for deploying mock ERC20 tokens and Chainlik oracle that are need on
contract PreMip00Script is Script, Test {
    uint256 public constant initialMintAmount = 1 ether;

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

        FaucetTokenWithPermit usdc = new FaucetTokenWithPermit(
            1e18,
            "USDBC",
            6,
            "USDBC"
        );
        FaucetTokenWithPermit cbETH = new FaucetTokenWithPermit(
            1e18,
            "Coinbase Wrapped Staked ETH",
            18, /// cbETH is 18 decimals
            "cbETH"
        );

        cbETH.allocateTo(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            initialMintAmount
        );

        MockWeth weth = new MockWeth();

        // Chainlink oracles

        MockChainlinkOracle usdcOracle = new MockChainlinkOracle(1e18, 6);
        MockChainlinkOracle ethOracle = new MockChainlinkOracle(2_000e18, 18);

        vm.stopBroadcast();

        addresses.addAddress("USDBC", address(usdc), true);
        addresses.addAddress("cbETH", address(cbETH), true);
        addresses.addAddress("WETH", address(weth), true);

        addresses.addAddress("USDC_ORACLE", address(usdcOracle), true);
        addresses.addAddress("ETH_ORACLE", address(ethOracle), true);
        addresses.addAddress("USDC_ORACLE", address(usdcOracle), true);

        vm.startBroadcast(PRIVATE_KEY);
        
        // cbETH is a composite oracle
        MockChainlinkOracle oracle = new MockChainlinkOracle(1.04296945e18, 18);
        ChainlinkCompositeOracle cbEthOracle = new ChainlinkCompositeOracle(
            addresses.getAddress("ETH_ORACLE"),
            address(oracle),
            address(0)
        );

        vm.stopBroadcast();

        addresses.addAddress("cbETH_ORACLE", address(cbEthOracle), true);
    }
}

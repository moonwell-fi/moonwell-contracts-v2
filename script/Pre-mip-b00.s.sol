// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";

/*
to run:
forge script script/Pre-mip-b00.s.sol -vvvv --rpc-url baseSepolia --broadcast --etherscan-api-key baseSepolia --slow
*/
// Script for deploying ERC20 tokens and oracles mocks to be used for MIP-B00 on base sepolia.
contract PreMipB00Script is Script, Test {
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

        MockWeth weth = new MockWeth();

        // Chainlink oracles

        MockChainlinkOracle usdcOracle = new MockChainlinkOracle(1e18, 6);
        MockChainlinkOracle ethOracle = new MockChainlinkOracle(2_000e18, 18);

        vm.stopBroadcast();

        addresses.addAddress("USDBC", address(usdc));
        addresses.addAddress("cbETH", address(cbETH));
        addresses.addAddress("WETH", address(weth));

        addresses.addAddress("USDC_ORACLE", address(usdcOracle));
        addresses.addAddress("ETH_ORACLE", address(ethOracle));

        vm.startBroadcast(PRIVATE_KEY);

        // cbETH is a composite oracle
        MockChainlinkOracle oracle = new MockChainlinkOracle(1.04296945e18, 18);
        ChainlinkCompositeOracle cbEthOracle = new ChainlinkCompositeOracle(
            addresses.getAddress("ETH_ORACLE"),
            address(oracle),
            address(0)
        );

        vm.stopBroadcast();

        addresses.addAddress("cbETH_ORACLE", address(cbEthOracle));

        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 i = 0; i < recordedNames.length; i++) {
            console.log("Deployed", recordedAddresses[i], recordedNames[i]);
        }

        console.log("New addresses after deploy:");

        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log(
                "        'name': '%s'\n}%s",
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }
}

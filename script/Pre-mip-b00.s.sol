// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {ChainlinkCompositeOracle} from
    "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {FaucetTokenWithPermit} from "@test/helper/FaucetToken.sol";
import {MockChainlinkOracle} from "@test/mock/MockChainlinkOracle.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";

/*
to run:
forge script script/Pre-mip-b00.s.sol -vvvv --rpc-url baseSepolia --broadcast --etherscan-api-key baseSepolia --slow
*/
// Script for deploying ERC20 tokens and oracles mocks to be used for MIP-B00 on base sepolia.
contract PreMipB00Script is Script, Test {
    uint256 public constant initialMintAmount = 1 ether;

    Addresses public addresses;

    function setUp() public {
        addresses = new Addresses();
    }

    function run() public {
        vm.startBroadcast();

        FaucetTokenWithPermit usdc =
            new FaucetTokenWithPermit(1e18, "USDBC", 6, "USDBC");
        FaucetTokenWithPermit cbETH = new FaucetTokenWithPermit(
            1e18,
            "Coinbase Wrapped Staked ETH",
            18,
            /// cbETH is 18 decimals
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

        vm.startBroadcast();

        // cbETH is a composite oracle
        MockChainlinkOracle oracle = new MockChainlinkOracle(1.04296945e18, 18);
        ChainlinkCompositeOracle cbEthOracle = new ChainlinkCompositeOracle(
            addresses.getAddress("ETH_ORACLE"), address(oracle), address(0)
        );

        vm.stopBroadcast();

        addresses.addAddress("cbETH_ORACLE", address(cbEthOracle));

        (string[] memory recordedNames,, address[] memory recordedAddresses) =
            addresses.getRecordedAddresses();
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

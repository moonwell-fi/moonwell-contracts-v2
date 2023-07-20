// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MToken} from "@protocol/core/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/core/Comptroller.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/core/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

contract LiveSystemIntegrationTest is Test {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(true);
        addresses = proposals.addresses();

        console.log("chainid: ", block.chainid);

        Configs(address(proposals.proposals(0))).init(addresses); /// init configs so 
        proposals.testProposals(true, false, false, true, true, false, false); /// build, and run, do not validate
    }

    function testMintMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e6;
        
        IERC20 token = IERC20(addresses.getAddress("USDC"));
        MErc20Delegator mToken = MErc20Delegator(payable(addresses.getAddress("MOONWELL_USDC")));
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        deal(address(token), sender, mintAmount);
        token.approve(address(mToken), mintAmount);

        assertEq(mToken.mint(mintAmount), 0); /// ensure successful mint
        assertEq(mToken.balanceOf(sender), mintAmount); /// ensure balance is correct
        assertEq(token.balanceOf(address(mToken)) - startingTokenBalance, mintAmount); /// ensure underlying balance is sent to mToken
    }

}

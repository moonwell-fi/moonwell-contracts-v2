// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {mipb02 as mip} from "@proposals/mips/mip-b02/mip-b02.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MToken} from "@protocol/MToken.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";

import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MaliciousBorrower} from "@test/mock/MaliciousBorrower.sol";

import {BASE_FORK_ID, MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";

/// verify that the new MWETH Delegate and Unwrapper are working as expected
contract WETHPostProposalCheck is Configs, PostProposalCheck {
    WethUnwrapper unwrapper;
    Comptroller comptroller;
    MErc20Delegator mToken;
    MWethDelegate delegate;
    WETHRouter router;
    bool ethReceived;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mToken = MErc20Delegator(payable(addresses.getAddress("MOONWELL_WETH")));
        router = WETHRouter(payable(addresses.getAddress("WETH_ROUTER")));

        unwrapper = new WethUnwrapper(addresses.getAddress("WETH"));

        delegate = new MWethDelegate(address(unwrapper));

        vm.prank(addresses.getAddress("TEMPORAL_GOVERNOR"));
        mToken._setImplementation(address(delegate), false, "");
    }

    function testSetup() public view {
        assertEq(delegate.wethUnwrapper(), address(unwrapper), "unwrapper incorrectly set");

        assertEq(
            MWethDelegate(address(mToken)).wethUnwrapper(),
            address(unwrapper),
            "unwrapper incorrectly set on mToken proxy"
        );

        assertEq(mToken.implementation(), address(delegate), "delegate incorrectly set");
    }

    function testMintMWethMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e18;

        IERC20 token = IERC20(addresses.getAddress("WETH"));

        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        vm.deal(sender, mintAmount);

        /// fund with raw eth
        token.approve(address(mToken), mintAmount);

        router.mint{value: mintAmount}(address(this));

        /// ensure successful mint
        assertTrue(mToken.balanceOf(sender) > 0);
        /// ensure balance is gt 0
        assertEq(token.balanceOf(address(mToken)) - startingTokenBalance, mintAmount);
        /// ensure underlying balance is sent to mToken

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(comptroller.checkMembership(sender, MToken(addresses.getAddress("MOONWELL_WETH"))));
        /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller.getAccountLiquidity(address(this));

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, mintAmount * 1_000, "liquidity not correct");
        assertEq(shortfall, 0, "Incorrect shortfall");

        assertEq(comptroller.exitMarket(address(mToken)), 0, "exit market failed");

        assertFalse(comptroller.checkMembership(sender, MToken(addresses.getAddress("MOONWELL_WETH"))));
        /// ensure sender and mToken is not in market
    }

    function testRedeemSendsRawEthToReceiver() public {
        testMintMWethMTokenSucceeds();
        assertFalse(ethReceived, "should not have received eth");

        uint256 redeemAmount = 100e18;
        uint256 startingBalance = address(this).balance;

        vm.warp(block.timestamp + 1000);

        /// accrue enough interest to redeem at least 100 eth

        assertEq(mToken.redeemUnderlying(redeemAmount), 0, "redeem failure");

        assertTrue(ethReceived, "should have received eth");

        uint256 endingBalance = address(this).balance;

        assertEq(endingBalance - startingBalance, redeemAmount, "incorrect eth amount after redemption");
    }

    receive() external payable {
        ethReceived = true;
    }
}

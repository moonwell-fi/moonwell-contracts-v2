// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_FORK_ID} from "@utils/ChainIds.sol";

/// @notice Ethereum-fork mirror of WETHPostProposalCheck (Base). MIP-E01 is
/// registered with id:0 in mips.json, so PostProposalCheck.setUp() auto-simulates
/// it on the Ethereum fork — repointing MOONWELL_WETH at a freshly deployed
/// MWethDelegate wired to a WethUnwrapper. Unlike the Base test (which manually
/// deploys + wires the delegate because MIP-B02 is not re-simulated), these tests
/// assert the proposal itself produced correct per-chain wiring (right WETH
/// address, right unwrapper constructor arg) and that redeem pays out native ETH
/// on Ethereum.
contract WETHPostProposalCheckEthereum is Configs, PostProposalCheck {
    Comptroller comptroller;
    MErc20Delegator mToken;
    WETHRouter router;
    bool ethReceived;

    function setUp() public override {
        super.setUp();

        vm.selectFork(ETHEREUM_FORK_ID);

        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        router = WETHRouter(payable(addresses.getAddress("WETH_ROUTER")));
    }

    /// @notice MIP-E01 must have repointed the Ethereum WETH market at the
    /// MWethDelegate wired to the WETH_UNWRAPPER (which itself references WETH).
    function testSetup() public view {
        assertEq(
            mToken.implementation(),
            addresses.getAddress("MWETH_IMPLEMENTATION"),
            "MWethDelegate not wired on Ethereum WETH market"
        );
        assertEq(
            MWethDelegate(address(mToken)).wethUnwrapper(),
            addresses.getAddress("WETH_UNWRAPPER"),
            "unwrapper not wired on Ethereum mToken proxy"
        );
        assertEq(
            WethUnwrapper(payable(addresses.getAddress("WETH_UNWRAPPER")))
                .weth(),
            addresses.getAddress("WETH"),
            "unwrapper references wrong WETH on Ethereum"
        );
    }

    function testMintMWethMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e18;

        IERC20 token = IERC20(addresses.getAddress("WETH"));

        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        vm.deal(sender, mintAmount); /// fund with raw eth
        router.mint{value: mintAmount}(address(this)); /// ensure successful mint

        assertTrue(mToken.balanceOf(sender) > 0, "mToken balance not gt 0");
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount,
            "underlying not sent to mToken"
        );
    }

    function testRedeemSendsRawEthToReceiver() public {
        testMintMWethMTokenSucceeds();
        assertFalse(ethReceived, "should not have received eth");

        uint256 redeemAmount = 100e18;
        uint256 startingBalance = address(this).balance;

        vm.warp(block.timestamp + 1000); /// accrue interest so 100 eth is redeemable

        assertEq(mToken.redeemUnderlying(redeemAmount), 0, "redeem failure");

        assertTrue(ethReceived, "should have received eth");

        assertEq(
            address(this).balance - startingBalance,
            redeemAmount,
            "incorrect eth amount after redemption"
        );
    }

    receive() external payable {
        ethReceived = true;
    }
}

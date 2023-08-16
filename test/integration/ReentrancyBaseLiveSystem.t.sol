// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mipb02 as mip} from "@test/proposals/mips/mip-b02/mip-b02.sol";
import {TestProposals} from "@test/proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MaliciousBorrower} from "@test/mock/MaliciousBorrower.sol";
import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";

contract ReentrancyLiveSystemBaseTest is
    Test,
    Configs,
    ComptrollerErrorReporter
{
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    WETHRouter router;

    function setUp() public {
        address[] memory mips = new address[](1);
        mips[0] = address(new mip());

        proposals = new TestProposals(mips);
        proposals.setUp();
        addresses = proposals.addresses();
        proposals.testProposals(
            false,
            true,
            false,
            false,
            true,
            true,
            false,
            true
        ); /// only setup after deploy, build, and run, do not validate
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        router = WETHRouter(payable(addresses.getAddress("WETH_ROUTER")));
    }

    function testMintMWethMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e18;

        IERC20 token = IERC20(addresses.getAddress("WETH"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        vm.deal(sender, mintAmount); /// fund with raw eth
        token.approve(address(mToken), mintAmount);

        router.mint{value: mintAmount}(address(this)); /// ensure successful mint
        assertTrue(mToken.balanceOf(sender) > 0); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount
        ); /// ensure underlying balance is sent to mToken

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        ); /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        assertEq(err, 0, "Error getting account liquidity");
        assertGt(liquidity, mintAmount * 1_000, "liquidity not correct");
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
    }

    function testReentrantBorrowFails() public {
        testMintMWethMTokenSucceeds(); /// top up weth market with liquidity

        address mToken = addresses.getAddress("MOONWELL_WETH");
        MaliciousBorrower borrower = new MaliciousBorrower(mToken, false);

        deal(addresses.getAddress("WETH"), address(borrower), 100e18); /// fund attack contract with weth

        vm.expectRevert("re-entered"); /// cannot reenter and borrow
        borrower.exploit();
    }

    function testReentrantExitMarketFails() public {
        testMintMWethMTokenSucceeds(); /// top up weth market with liquidity

        address mToken = addresses.getAddress("MOONWELL_WETH");
        /// cross contract reentrancy attempt this time
        MaliciousBorrower borrower = new MaliciousBorrower(mToken, true);

        deal(addresses.getAddress("WETH"), address(borrower), 100e18); /// fund attack contract with weth

        vm.expectEmit(true, true, true, true, address(comptroller));
        /// cannot reenter and borrow
        emit Failure(
            uint256(Error.NONZERO_BORROW_BALANCE),
            uint256(FailureInfo.EXIT_MARKET_BALANCE_OWED),
            0
        );
        borrower.exploit();

        console.log(
            "weth balance: ",
            IERC20(addresses.getAddress("WETH")).balanceOf(address(borrower))
        ); /// ensure borrow failed
        console.log(
            "mToken balance: ",
            IERC20(mToken).balanceOf(address(borrower))
        ); /// ensure borrow failed
    }
}

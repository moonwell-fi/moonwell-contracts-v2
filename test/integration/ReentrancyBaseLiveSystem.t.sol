// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";
import "@utils/ChainIds.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mipb02 as mip} from "@proposals/mips/mip-b02/mip-b02.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MaliciousBorrower} from "@test/mock/MaliciousBorrower.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract ReentrancyPostProposalTest is
    Configs,
    PostProposalCheck,
    ComptrollerErrorReporter
{
    Comptroller comptroller;
    WETHRouter router;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

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

        assertEq(
            comptroller.exitMarket(address(mToken)),
            0,
            "exit market failed"
        );

        assertFalse(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_WETH"))
            )
        ); /// ensure sender and mToken is not in market
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

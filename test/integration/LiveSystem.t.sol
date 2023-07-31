// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

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

contract LiveSystemTest is Test {
    TestProposals proposals;
    Addresses addresses;

    function setUp() public {
        proposals = new TestProposals();
        proposals.setUp();
        proposals.setDebug(true);
        addresses = proposals.addresses();
        proposals.testProposals(true, true, true, true, true, false, false); /// deploy, after deploy, build, and run, do not validate
    }

    function testSetup() public {
        Configs.EmissionConfig[] memory configs = Configs(
            address(proposals.proposals(0))
        ).getEmissionConfigurations(block.chainid);
        Configs.CTokenConfiguration[] memory mTokenConfigs = Configs(
            address(proposals.proposals(0))
        ).getCTokenConfigurations(block.chainid);

        assertEq(configs.length, 5); /// 5 configs on base goerli
        assertEq(mTokenConfigs.length, 5); /// 5 mTokens on base goerli
    }

    function testMintMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = 100e6;

        IERC20 token = IERC20(addresses.getAddress("USDC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDC"))
        );
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        deal(address(token), sender, mintAmount);
        token.approve(address(mToken), mintAmount);

        assertEq(mToken.mint(mintAmount), 0); /// ensure successful mint
        assertTrue(mToken.balanceOf(sender) > 0); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount
        ); /// ensure underlying balance is sent to mToken
    }

    function testBorrowMTokenSucceeds() public {
        testMintMTokenSucceeds();

        address sender = address(this);
        uint256 borrowAmount = 50e6;

        IERC20 token = IERC20(addresses.getAddress("USDC"));
        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_USDC"))
        );
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        uint256 startingTokenBalance = token.balanceOf(sender);

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(sender, MToken(address(mToken)))
        ); /// ensure sender and mToken is in market

        assertEq(mToken.borrow(borrowAmount), 0); /// ensure successful borrow

        assertEq(token.balanceOf(sender), borrowAmount); /// ensure balance is correct
    }

    function testBorrowOtherMTokenSucceeds() public {
        testMintMTokenSucceeds();

        address sender = address(this);
        deal(
            addresses.getAddress("WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            1 ether
        );

        IERC20 weth = IERC20(addresses.getAddress("WETH"));

        uint256 borrowAmount = 1e6;

        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        // mToken.mint(0.001 ether);
        uint256 startingTokenBalance = weth.balanceOf(sender);

        address[] memory mTokens = new address[](1);
        mTokens[0] = addresses.getAddress("MOONWELL_USDC");

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_USDC"))
            )
        ); /// ensure sender and mToken is in market

        (, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(sender);

        assertEq(mToken.borrow(borrowAmount), 0); /// ensure successful borrow

        assertEq(weth.balanceOf(sender), borrowAmount); /// ensure balance is correct
    }
}

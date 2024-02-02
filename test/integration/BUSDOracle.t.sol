// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {mipb02 as mip} from "@proposals/mips/mip-b02/mip-b02.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/Oracles/ChainlinkOracle.sol";
import {MaliciousBorrower} from "@test/mock/MaliciousBorrower.sol";
import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {MErc20Storage, MErc20Interface} from "@protocol/MTokenInterfaces.sol";

contract BUSDOracle is Test, Configs, ComptrollerErrorReporter {
    Comptroller comptroller;
    TestProposals proposals;
    Addresses addresses;
    WETHRouter router;
    MToken mBUSD;

    mapping(address => uint256) public liquidity;
    mapping(address => uint256) public shortfall;

    address[] public users = [
        0x7f85c38d42C22e3C2e82590f0234901757D77218,
        0x79a2e3F31680Cdd2C8223d22BA81d41C47405c96,
        0x0bbC74a467Ff35a0edDf21b53F71feA7E98872d6
        // ,
        // 0xEEAf9F8E7a42273d091Dd89091B16d3cf08B8101
    ];

    function setUp() public {
        addresses = new Addresses();
        mBUSD = MToken(0x298f2E346b82D69a473BF25f329BDF869e17dEc8);
        comptroller = Comptroller(address(mBUSD.comptroller()));
    }

    function testWarpToFutureClBUSDCorrect() public {
        require(mBUSD.accrueInterest() == 0, "accrueInterest failed");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 balance = mBUSD.balanceOf(user);

            (uint256 err, uint256 _liquidity, uint256 _shortfall) = comptroller
                .getAccountLiquidity(user);

            require(err == 0, "getAccountLiquidity failed");

            liquidity[user] = _liquidity;
            shortfall[user] = _shortfall;
        }

        vm.warp(block.timestamp + 300 days);
        vm.roll(block.number + 300 days / 12); /// roll forward by block numbers passing

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 balance = mBUSD.balanceOf(user);

            (uint256 err, uint256 _liquidity, uint256 _shortfall) = comptroller
                .getAccountLiquidity(user);

            require(err == 0, "getAccountLiquidity failed");

            require(
                liquidity[user] == _liquidity,
                "liquidity mismatch post proposal"
            );
            require(
                shortfall[user] == _shortfall,
                "shortfall mismatch post proposal"
            );

            liquidity[user] = 0;
            shortfall[user] = 0;
        }

        require(
            mBUSD.accrueInterest() == 0,
            "accrueInterest failed after warp"
        );
    }

    function testWarpToFutureClBUSDCorrectAndPriceHardcodedByAdmin() public {
        uint256 newUnderlyingPrice = 999592350000000000;
        ChainlinkOracle chainlinkOracle = ChainlinkOracle(
            0xED301cd3EB27217BDB05C4E9B820a8A3c8B665f9
        );

        vm.prank(addresses.getAddress("MOONBEAM_TIMELOCK"));
        chainlinkOracle.setUnderlyingPrice(mBUSD, newUnderlyingPrice);
        assertEq(
            chainlinkOracle.getUnderlyingPrice(mBUSD),
            newUnderlyingPrice,
            "underlying price incorrect"
        );

        require(mBUSD.accrueInterest() == 0, "accrueInterest failed");

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 balance = mBUSD.balanceOf(user);

            (uint256 err, uint256 _liquidity, uint256 _shortfall) = comptroller
                .getAccountLiquidity(user);

            require(err == 0, "getAccountLiquidity failed");

            liquidity[user] = _liquidity;
            shortfall[user] = _shortfall;
        }

        vm.warp(block.timestamp + 300 days);
        vm.roll(block.number + 300 days / 12); /// roll forward by block numbers passing

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 balance = mBUSD.balanceOf(user);

            (uint256 err, uint256 _liquidity, uint256 _shortfall) = comptroller
                .getAccountLiquidity(user);

            require(err == 0, "getAccountLiquidity failed");

            require(
                liquidity[user] == _liquidity,
                "liquidity mismatch post proposal"
            );
            require(
                shortfall[user] == _shortfall,
                "shortfall mismatch post proposal"
            );

            liquidity[user] = 0;
            shortfall[user] = 0;
        }

        require(
            mBUSD.accrueInterest() == 0,
            "accrueInterest failed after warp"
        );
    }

    function testGetAssetsIn() public {
        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            MToken[] memory assets = comptroller.getAssetsIn(user);

            console.log("user: ", user);
            for (uint256 j = 0; j < assets.length; j++) {
                console.log("asssets for user: ", address(assets[j]));
            }
        }
    }

    function testSupplyingAndBorrowingPostWarp() public {
        testWarpToFutureClBUSDCorrectAndPriceHardcodedByAdmin();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            MToken[] memory assets = comptroller.getAssetsIn(user);

            console.log("user: ", user);
            for (uint256 j = 0; j < assets.length; j++) {
                console.log("assets for user: ", address(assets[j]));

                if (
                    address(mBUSD) == address(assets[j]) ||
                    addresses.getAddress("MGLIMMER") == address(assets[j])
                ) {
                    continue;
                }

                address underlying = MErc20Storage(address(assets[j]))
                    .underlying();

                deal(underlying, user, 1e18);

                vm.startPrank(user);
                MToken(underlying).approve(address(assets[j]), 1e18);

                require(
                    MErc20Interface(address(assets[j])).mint(1e18) == 0,
                    "mint failed"
                );
                require(
                    MErc20Interface(address(assets[j])).borrow(1e6) == 0,
                    "borrow failed"
                );

                vm.stopPrank();
            }
        }
    }
}

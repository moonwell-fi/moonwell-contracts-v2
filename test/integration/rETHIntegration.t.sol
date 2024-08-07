// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@forge-std/Test.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {TestProposals} from "@proposals/TestProposals.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract rETHLiveSystemBasePostProposalTest is Test, PostProposalCheck {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    address well;
    MErc20 mwstETH;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

        well = addresses.getAddress("GOVTOKEN");
        mwstETH = MErc20(addresses.getAddress("MOONWELL_rETH"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        mwstETH.accrueInterest();
    }

    function testSetupmwstETH() public {
        assertEq(address(mwstETH.underlying()), addresses.getAddress("rETH"));
        assertEq(mwstETH.name(), "Moonwell Rocket Ether");
        assertEq(mwstETH.symbol(), "mrETH");
        assertEq(mwstETH.decimals(), 8);
        assertGt(
            mwstETH.exchangeRateCurrent(),
            0.0002e18,
            "incorrect starting exchange rate"
        ); /// exchange starting price is 0.0002e18
        assertGt(
            mwstETH.reserveFactorMantissa(),
            0.01e18,
            "incorrect reserve factor"
        );
        assertEq(
            address(mwstETH.comptroller()),
            addresses.getAddress("UNITROLLER")
        );
    }

    function testEmissionsAdminCanChangeRewardStream() public {
        address emissionsAdmin = addresses.getAddress("EMISSIONS_ADMIN");

        vm.prank(emissionsAdmin);
        mrd._updateOwner(mwstETH, address(well), emissionsAdmin);

        vm.prank(emissionsAdmin);
        mrd._updateBorrowSpeed(mwstETH, address(well), 1e18);
    }

    function testSupplyingOverSupplyCapFails() public {
        uint256 mintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_rETH")
        ) + 1;
        address underlying = address(mwstETH.underlying());
        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mwstETH), mintAmount);
        vm.expectRevert("market supply cap reached");
        mwstETH.mint(mintAmount);
    }

    function testBorrowingOverBorrowCapFails() public {
        uint256 mintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_rETH")
        );
        /// filter out case where no minting allowed
        if (mintAmount == 0) {
            return;
        }
        uint256 borrowAmount = _getMaxBorrowAmount(
            addresses.getAddress("MOONWELL_rETH")
        );
        /// filter out case where no borrowing allowed
        if (borrowAmount == 0) {
            return;
        }
        borrowAmount += 100;

        address underlying = address(mwstETH.underlying());

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mwstETH), mintAmount);
        mwstETH.mint(mintAmount);

        address[] memory mToken = new address[](1);
        mToken[0] = address(mwstETH);

        comptroller.enterMarkets(mToken);

        vm.expectRevert("market borrow cap reached");
        mwstETH.borrow(borrowAmount);
    }

    function testMintwstETHMTokenSucceeds() public {
        address sender = address(this);
        uint256 mintAmount = _getMaxSupplyAmount(
            addresses.getAddress("MOONWELL_rETH")
        ) / 2;

        /// filter out zero mint case
        if (mintAmount == 0) {
            return;
        }

        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_rETH"))
        );
        IERC20 token = IERC20(mToken.underlying());
        uint256 startingTokenBalance = token.balanceOf(address(mToken));

        deal(address(token), sender, mintAmount);
        token.approve(address(mToken), mintAmount);

        assertEq(mToken.mint(mintAmount), 0, "mint failure"); /// ensure successful mint
        assertTrue(mToken.balanceOf(sender) > 0, "balance incorrect"); /// ensure balance is gt 0
        assertEq(
            token.balanceOf(address(mToken)) - startingTokenBalance,
            mintAmount,
            "mToken underlying balance incorrect"
        ); /// ensure underlying balance is sent to mToken

        address[] memory mTokens = new address[](1);
        mTokens[0] = address(mToken);

        comptroller.enterMarkets(mTokens);
        assertTrue(
            comptroller.checkMembership(
                sender,
                MToken(addresses.getAddress("MOONWELL_rETH"))
            )
        ); /// ensure sender and mToken is in market

        (uint256 err, uint256 liquidity, uint256 shortfall) = comptroller
            .getAccountLiquidity(address(this));

        (, uint256 collateralFactor) = comptroller.markets(address(mToken)); /// fetch collateral factor

        uint256 price = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        ).getUnderlyingPrice(MToken(address(mToken)));

        assertEq(err, 0, "Error getting account liquidity");
        assertApproxEqRel(
            liquidity,
            (mintAmount * price * collateralFactor) / 1e36, /// trim off both the CF and Chainlink Price feed extra precision
            1e13,
            "liquidity not within .001% of given CF"
        );
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateBorrowSpeed(
            MToken(addresses.getAddress("MOONWELL_rETH")), /// reward mwstETH
            well, /// rewards paid in WELL
            1e18 /// pay 1 well per second in rewards to borrowers
        );
        vm.stopPrank();

        deal(
            well,
            address(mrd),
            4 weeks * 1e18 /// fund for entire period
        );

        MultiRewardDistributorCommon.MarketConfig memory config = mrd
            .getConfigForMarket(
                MToken(addresses.getAddress("MOONWELL_rETH")),
                addresses.getAddress("GOVTOKEN")
            );

        assertEq(
            config.owner,
            addresses.getAddress("EMISSIONS_ADMIN"),
            "incorrect admin"
        );
        assertEq(config.emissionToken, well, "incorrect reward token");
        assertEq(config.borrowEmissionsPerSec, 1e18, "incorrect reward rate");
    }

    function _getMaxSupplyAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 supplyCap = comptroller.supplyCaps(address(mToken));

        uint256 totalCash = MToken(mToken).getCash();
        uint256 totalBorrows = MToken(mToken).totalBorrows();
        uint256 totalReserves = MToken(mToken).totalReserves();

        // totalSupplies = totalCash + totalBorrows - totalReserves
        uint256 totalSupplies = (totalCash + totalBorrows) - totalReserves;

        if (totalSupplies - 1 > supplyCap) {
            return 0;
        }

        return supplyCap - totalSupplies - 1;
    }

    function _getMaxBorrowAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = MToken(mToken).totalBorrows();

        return borrowCap - totalBorrows - 1;
    }
}

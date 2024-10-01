// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MarketBase} from "@test/utils/MarketBase.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";

contract wstETHPostProposalTest is PostProposalCheck {
    MultiRewardDistributor mrd;
    Comptroller comptroller;
    address well;
    MErc20 mwstETH;
    MarketBase public marketBase;

    function setUp() public override {
        super.setUp();

        vm.selectFork(BASE_FORK_ID);

        well = addresses.getAddress("GOVTOKEN");
        mwstETH = MErc20(addresses.getAddress("MOONWELL_wstETH"));
        comptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        marketBase = new MarketBase(comptroller);
        mrd = MultiRewardDistributor(addresses.getAddress("MRD_PROXY"));
        mwstETH.accrueInterest();
    }

    function testSetupmwstETH() public {
        assertEq(address(mwstETH.underlying()), addresses.getAddress("wstETH"));
        assertEq(mwstETH.name(), "Moonwell Wrapped Lido Staked Ether");
        assertEq(mwstETH.symbol(), "mwstETH");
        assertEq(mwstETH.decimals(), 8);
        assertGt(
            mwstETH.exchangeRateCurrent(),
            0.0002e18,
            "incorrect starting exchange rate"
        ); /// exchange starting price is 0.0002e18
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
        uint256 mintAmount = marketBase.getMaxSupplyAmount(
            MToken(addresses.getAddress("MOONWELL_wstETH"))
        ) + 1;

        if (mintAmount == 1) {
            vm.skip(true);
        }

        address underlying = address(mwstETH.underlying());
        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(address(mwstETH), mintAmount);
        vm.expectRevert("market supply cap reached");
        mwstETH.mint(mintAmount);
    }

    function testBorrowingOverBorrowCapFails() public {
        uint256 mintAmount = marketBase.getMaxSupplyAmount(
            MToken(addresses.getAddress("MOONWELL_wstETH"))
        );

        if (mintAmount == 1 || mintAmount < 1e18) {
            vm.skip(true);
        }

        mintAmount -= 1e18;

        uint256 borrowAmount = _getMaxBorrowAmount(
            addresses.getAddress("MOONWELL_wstETH")
        ) + 100;
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
        uint256 mintAmount = marketBase.getMaxSupplyAmount(
            MToken(addresses.getAddress("MOONWELL_wstETH"))
        );

        if (mintAmount == 0) {
            vm.skip(true);
        }

        MErc20Delegator mToken = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_wstETH"))
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
                MToken(addresses.getAddress("MOONWELL_wstETH"))
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
            1e14,
            "liquidity not within 0.01% of given CF"
        );
        assertEq(shortfall, 0, "Incorrect shortfall");

        comptroller.exitMarket(address(mToken));
    }

    function testUpdateEmissionConfigBorrowUsdcSuccess() public {
        vm.startPrank(addresses.getAddress("EMISSIONS_ADMIN"));
        mrd._updateBorrowSpeed(
            MToken(addresses.getAddress("MOONWELL_wstETH")), /// reward mwstETH
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
                MToken(addresses.getAddress("MOONWELL_wstETH")),
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

    function _getMaxBorrowAmount(
        address mToken
    ) internal view returns (uint256) {
        uint256 borrowCap = comptroller.borrowCaps(address(mToken));
        uint256 totalBorrows = MToken(mToken).totalBorrows();

        return borrowCap - totalBorrows - 1;
    }
}

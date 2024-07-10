// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";

import {FeeSplitter} from "@protocol/morpho/FeeSplitter.sol";

import {IMetaMorpho, MarketParams} from "@protocol/morpho/IMetaMorpho.sol";
import {IMetaMorphoFactory} from "@protocol/morpho/IMetaMorphoFactory.sol";
import {IMorphoBlue} from "@protocol/morpho/IMorphoBlue.sol";

contract FeeSplitterLiveSystemBaseTest is Test {
    /// @notice the addresses contract
    Addresses addresses;

    /// @notice the weth token
    ERC20 public weth;

    /// @notice the usdc token
    ERC20 public usdc;

    /// @notice the weth mToken
    address public mWeth;

    /// @notice the usdc mToken
    address public mUsdc;

    /// @notice reward recipient `B`, receives the rewards directly
    address public rewardRecipientB = address(0xaaaaaaaa);

    IMetaMorphoFactory public factory;

    IMetaMorpho public metaMorphoUsdc;

    IMetaMorpho public metaMorphoWeth;

    /// @notice usdc splitter
    FeeSplitter public usdcSplitter;

    /// @notice weth splitter
    FeeSplitter public wethSplitter;

    uint256 public constant TIMELOCK = 1 days;

    bytes32 public constant CBETH_USDC_MARKET_ID = 0xdba352d93a64b17c71104cbddc6aef85cd432322a1446b5b65163cbbc615cd0c;

    /// @notice The length of the data used to compute the id of a market.
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each.
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    function setUp() public {
        /// addresses
        addresses = new Addresses();

        factory = IMetaMorphoFactory(addresses.getAddress("META_MORPHO_FACTORY"));
        usdc = ERC20(addresses.getAddress("USDC"));
        weth = ERC20(addresses.getAddress("WETH"));
        mWeth = addresses.getAddress("MOONWELL_WETH");
        mUsdc = addresses.getAddress("MOONWELL_USDC");

        /// deployments
        metaMorphoUsdc = IMetaMorpho(
            factory.createMetaMorpho(
                address(this), TIMELOCK, address(usdc), "MetaMorpho USDC", "mUSDC", keccak256(abi.encodePacked("mUSDC"))
            )
        );
        metaMorphoWeth = IMetaMorpho(
            factory.createMetaMorpho(
                address(this), TIMELOCK, address(weth), "MetaMorpho WETH", "mWETH", keccak256(abi.encodePacked("mWETH"))
            )
        );

        usdcSplitter = new FeeSplitter(rewardRecipientB, 5_000, address(metaMorphoUsdc), mUsdc);

        wethSplitter = new FeeSplitter(rewardRecipientB, 5_000, address(metaMorphoWeth), mWeth);

        /// mint usdc

        uint256 usdcMintAmount = 1_000_000 * 1e6;
        deal(address(usdc), address(this), usdcMintAmount);

        MarketParams memory params = MarketParams({
            loanToken: address(usdc),
            collateralToken: addresses.getAddress("cbETH"),
            oracle: addresses.getAddress("MORPHO_CHAINLINK_cbETH_ORACLE"),
            irm: addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM"),
            lltv: 0.86e18
        });

        metaMorphoUsdc.submitCap(params, usdcMintAmount * 100);

        vm.warp(block.timestamp + 1 days);

        metaMorphoUsdc.acceptCap(params);
        bytes32[] memory newSupplyQueue = new bytes32[](1);
        newSupplyQueue[0] = CBETH_USDC_MARKET_ID;
        metaMorphoUsdc.setSupplyQueue(newSupplyQueue);

        usdc.approve(address(metaMorphoUsdc), usdcMintAmount);
        metaMorphoUsdc.deposit(usdcMintAmount, address(this));

        /// mint weth

        uint256 wethMintAmount = 1_000 * 1e18;
        deal(address(weth), address(this), wethMintAmount);

        params = MarketParams({
            loanToken: address(weth),
            collateralToken: addresses.getAddress("cbETH"),
            oracle: addresses.getAddress("MORPHO_CHAINLINK_cbETH_ORACLE"),
            irm: addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM"),
            lltv: 0.86e18
        });

        IMorphoBlue(addresses.getAddress("MORPHO_BLUE")).createMarket(params);
        bytes32 marketId = id(params);

        metaMorphoWeth.submitCap(params, wethMintAmount * 100);

        vm.warp(block.timestamp + 1 days);

        metaMorphoWeth.acceptCap(params);

        newSupplyQueue = new bytes32[](1);
        newSupplyQueue[0] = marketId;
        metaMorphoWeth.setSupplyQueue(newSupplyQueue);

        weth.approve(address(metaMorphoWeth), wethMintAmount);
        metaMorphoWeth.deposit(wethMintAmount, address(this));
    }

    function testSetup() public view {
        assertEq(usdcSplitter.b(), rewardRecipientB);
        assertEq(usdcSplitter.splitA(), 5_000);
        assertEq(usdcSplitter.splitB(), 5_000);
        assertEq(usdcSplitter.metaMorphoVault(), address(metaMorphoUsdc));
        assertEq(usdcSplitter.mToken(), mUsdc);
        assertEq(address(usdcSplitter.token()), address(usdc));

        assertEq(wethSplitter.b(), rewardRecipientB);
        assertEq(wethSplitter.splitA(), 5_000);
        assertEq(wethSplitter.splitB(), 5_000);
        assertEq(wethSplitter.metaMorphoVault(), address(metaMorphoWeth));
        assertEq(wethSplitter.mToken(), mWeth);
        assertEq(address(wethSplitter.token()), address(weth));
    }

    function testConstructionFailsUnderlyingAssetMismatch() public {
        /// weth vault, usdc mtoken
        vm.expectRevert("FeeSplitter: asset mismatch");
        new FeeSplitter(rewardRecipientB, 5_000, address(metaMorphoUsdc), mWeth);

        vm.expectRevert("FeeSplitter: asset mismatch");
        new FeeSplitter(rewardRecipientB, 5_000, address(metaMorphoWeth), mUsdc);
        /// weth mtoken, usdc vault
    }

    function testAddReservesReturnsNonZeroFails() public {
        vm.etch(address(mWeth), type(MockFailMErc20).runtimeCode);
        vm.expectRevert("FeeSplitter: add reserves failure");
        wethSplitter.split();
    }

    function testFeeSplitsAlwaysSumToTotal(uint256 splitA) public {
        splitA = bound(splitA, 0, 10_000);

        FeeSplitter splitter = new FeeSplitter(rewardRecipientB, splitA, address(metaMorphoWeth), mWeth);

        assertEq(splitter.splitA(), splitA, "split a");
        assertEq(splitter.splitB(), 10_000 - splitA, "split b");
        assertEq(splitter.splitA() + splitter.splitB(), 10_000, "split sum");
    }

    function testWethSplit() public {
        /// accrue fee
        metaMorphoWeth.deposit(0, address(this));
        uint256 splitAmount = metaMorphoWeth.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoWeth.transfer(address(wethSplitter), splitAmount);
        assertEq(MErc20(mWeth).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mWeth).totalReserves();
        uint256 startingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);

        wethSplitter.split();

        uint256 endingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mWeth).totalReserves();

        assertEq(endingWethSharesBalance, startingWethSharesBalance + splitAmount / 2, "weth shares balance");
        assertApproxEqAbs(
            endingReserves, startingReserves + metaMorphoWeth.previewRedeem(splitAmount / 2), 1, "reserves balance"
        );
    }

    function testWethSplitSixtyForty() public {
        wethSplitter = new FeeSplitter(rewardRecipientB, 6_000, address(metaMorphoWeth), mWeth);

        /// accrue fee
        metaMorphoWeth.deposit(0, address(this));
        uint256 splitAmount = metaMorphoWeth.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoWeth.transfer(address(wethSplitter), splitAmount);
        assertEq(MErc20(mWeth).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mWeth).totalReserves();
        uint256 startingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);

        wethSplitter.split();

        uint256 endingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mWeth).totalReserves();

        assertEq(
            endingWethSharesBalance, startingWethSharesBalance + (splitAmount * 4000) / 10_000, "weth shares balance"
        );
        assertApproxEqAbs(
            endingReserves,
            startingReserves + metaMorphoWeth.previewRedeem((splitAmount * 6000) / 10_000),
            1,
            "reserves balance"
        );
    }

    function testWethSplitSeventyThirty() public {
        wethSplitter = new FeeSplitter(rewardRecipientB, 7_000, address(metaMorphoWeth), mWeth);

        /// accrue fee
        metaMorphoWeth.deposit(0, address(this));
        uint256 splitAmount = metaMorphoWeth.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoWeth.transfer(address(wethSplitter), splitAmount);
        assertEq(MErc20(mWeth).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mWeth).totalReserves();
        uint256 startingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);

        wethSplitter.split();

        uint256 endingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mWeth).totalReserves();

        assertEq(
            endingWethSharesBalance, startingWethSharesBalance + (splitAmount * 3_000) / 10_000, "weth shares balance"
        );
        assertApproxEqAbs(
            endingReserves,
            startingReserves + metaMorphoWeth.previewRedeem((splitAmount * 7_000) / 10_000),
            1,
            "reserves balance"
        );
    }

    function testWethSplitFuzz(uint256 splitA) public {
        splitA = _bound(splitA, 1, 10_000);
        uint256 splitB = 10_000 - splitA;

        wethSplitter = new FeeSplitter(rewardRecipientB, splitA, address(metaMorphoWeth), mWeth);

        /// accrue fee
        metaMorphoWeth.deposit(0, address(this));
        uint256 splitAmount = metaMorphoWeth.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoWeth.transfer(address(wethSplitter), splitAmount);
        assertEq(MErc20(mWeth).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mWeth).totalReserves();
        uint256 startingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);

        wethSplitter.split();

        uint256 endingWethSharesBalance = metaMorphoWeth.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mWeth).totalReserves();

        assertEq(
            endingWethSharesBalance, startingWethSharesBalance + (splitAmount * splitB) / 10_000, "weth shares balance"
        );
        assertApproxEqAbs(
            endingReserves,
            startingReserves + metaMorphoWeth.previewRedeem((splitAmount * splitA) / 10_000),
            1,
            "reserves balance"
        );
    }

    function testUsdcSplit() public {
        /// accrue fee
        metaMorphoUsdc.deposit(0, address(this));
        uint256 splitAmount = metaMorphoUsdc.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoUsdc.transfer(address(usdcSplitter), splitAmount);
        assertEq(MErc20(mUsdc).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mUsdc).totalReserves();
        uint256 startingUsdcSharesBalance = metaMorphoUsdc.balanceOf(rewardRecipientB);

        usdcSplitter.split();

        uint256 endingUsdcSharesBalance = metaMorphoUsdc.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mUsdc).totalReserves();

        assertEq(endingUsdcSharesBalance, startingUsdcSharesBalance + splitAmount / 2, "weth shares balance");
        assertApproxEqAbs(
            endingReserves,
            startingReserves + metaMorphoUsdc.previewRedeem(splitAmount / 2),
            1,
            /// allow off by one in either direction
            "reserves balance"
        );
    }

    function testUsdcSplitFuzz(uint256 splitA) public {
        splitA = bound(splitA, 1_000, 8_000);
        uint256 splitB = 10_000 - splitA;

        usdcSplitter = new FeeSplitter(rewardRecipientB, splitA, address(metaMorphoUsdc), mUsdc);

        /// accrue fee
        metaMorphoUsdc.deposit(0, address(this));
        uint256 splitAmount = metaMorphoUsdc.balanceOf(address(this));

        /// donate 4626 tokens to the splitter
        metaMorphoUsdc.transfer(address(usdcSplitter), splitAmount);
        assertEq(MErc20(mUsdc).accrueInterest(), 0, "accrue interest failed");

        uint256 startingReserves = MErc20(mUsdc).totalReserves();
        uint256 startingUsdcSharesBalance = metaMorphoUsdc.balanceOf(rewardRecipientB);

        usdcSplitter.split();

        uint256 endingUsdcSharesBalance = metaMorphoUsdc.balanceOf(rewardRecipientB);
        uint256 endingReserves = MErc20(mUsdc).totalReserves();

        assertEq(
            endingUsdcSharesBalance, startingUsdcSharesBalance + (splitAmount * splitB) / 10_000, "weth shares balance"
        );
        assertApproxEqAbs(
            endingReserves,
            startingReserves + metaMorphoUsdc.previewRedeem((splitAmount * splitA) / 10_000),
            10,
            /// allow off by 10 and no more
            "reserves balance"
        );
    }

    function id(MarketParams memory marketParams) internal pure returns (bytes32 marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
        }
    }
}

contract MockFailMErc20 {
    function _addReserves(uint256) external pure returns (uint256) {
        return 1;
    }
}

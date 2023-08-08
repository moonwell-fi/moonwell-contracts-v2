pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {TransparentUpgradeableProxy, ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";
import {MockCToken} from "@test/mock/MockCToken.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";

import {MToken} from "@protocol/MToken.sol";
import {SigUtils} from "@test/helper/SigUtils.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20Immutable} from "@protocol/MErc20Immutable.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {InterestRateModel} from "@protocol/IRModels/InterestRateModel.sol";
import {MultiRewardDistributor} from "@protocol/MultiRewardDistributor/MultiRewardDistributor.sol";
import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {WhitePaperInterestRateModel} from "@protocol/IRModels/WhitePaperInterestRateModel.sol";

contract WETHRouterUnitTest is Test {
    MockWeth public weth;
    WETHRouter public router;
    Comptroller public comptroller;
    SimplePriceOracle public oracle;
    MErc20Immutable public mToken;
    InterestRateModel public irModel;
    SigUtils public sigUtils;
    MultiRewardDistributor public distributor;

    bool acceptEth;

    function setUp() public {
        comptroller = new Comptroller();
        oracle = new SimplePriceOracle();
        weth = new MockWeth();

        irModel = new WhitePaperInterestRateModel(0.1e18, 0.45e18);

        /// mWETH
        mToken = new MErc20Immutable(
            address(weth),
            comptroller,
            irModel,
            1e18, // Exchange rate is 1:1 for tests
            "Test mToken",
            "mTEST",
            8,
            payable(address(this))
        );

        distributor = new MultiRewardDistributor();
        bytes memory initdata = abi.encodeWithSignature(
            "initialize(address,address)",
            address(comptroller),
            address(this)
        );
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(distributor),
            address(this),
            initdata
        );
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);

        router = new WETHRouter(WETH9(address(weth)), MErc20(address(mToken)));
    }

    function testSetup() public {
        assertEq(address(router.weth()), address(weth));
        assertEq(address(router.mToken()), address(mToken));
    }

    function testRouterDepositMints() public {
        uint256 ethAmount = 1 ether;
        deal(address(this), ethAmount);

        router.mint{value: ethAmount}(address(this));

        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(mToken)), ethAmount);
        assertEq(mToken.balanceOf(address(this)), ethAmount);
        assertEq(address(this).balance, 0);
    }

    function testRouterRedeemSucceeds() public {
        testRouterDepositMints();
        mToken.approve(address(router), type(uint256).max);
        acceptEth = true;
        router.redeem(mToken.balanceOf(address(this)), address(this));
        assertEq(mToken.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
        assertEq(address(this).balance, 1 ether);
    }

    function testRouterRedeemFailsNoApproval() public {
        testRouterDepositMints();
        uint256 mTokenBalance = mToken.balanceOf(address(this));
        vm.expectRevert("SafeERC20: ERC20 operation did not succeed");
        router.redeem(mTokenBalance, address(this));
    }

    function testRouterRedeemFailsAcceptEthFalse() public {
        testRouterDepositMints();
        mToken.approve(address(router), type(uint256).max);
        acceptEth = false;
        uint256 redeemAmount = mToken.balanceOf(address(this));
        vm.expectRevert("WETHRouter: ETH transfer failed");
        router.redeem(redeemAmount, address(this));
    }

    function testMintFailsTokens() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        cToken.setError(true);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));

        vm.deal(address(this), 1 ether);

        vm.expectRevert("WETHRouter: mint failed");
        router.mint{value: 1 ether}(address(this));
    }

    function testRedeemFailsTokens() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));

        vm.deal(address(this), 1 ether);
        router.mint{value: 1 ether}(address(this));
        cToken.approve(address(router), type(uint256).max); /// max approve router to spend cToken

        cToken.setError(true);

        uint256 cTokenBalance = cToken.balanceOf(address(this));
        vm.expectRevert("WETHRouter: redeem failed");
        router.redeem(cTokenBalance, address(this));
    }

    function testSendEtherToWethRouterFails() public {
        vm.deal(address(this), 1 ether);

        vm.expectRevert("WETHRouter: not weth");
        (bool success, ) = address(router).call{value: 1 ether}("");
        success; /// shhhhh
    }

    receive() external payable {
        require(acceptEth, "Eth not accepted");
    }
}

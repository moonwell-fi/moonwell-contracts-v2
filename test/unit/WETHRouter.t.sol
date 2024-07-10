pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {
    ITransparentUpgradeableProxy,
    TransparentUpgradeableProxy
} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {WETH9} from "@protocol/router/IWETH.sol";

import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MockCToken} from "@test/mock/MockCToken.sol";
import {MockWeth} from "@test/mock/MockWeth.sol";

import {Comptroller} from "@protocol/Comptroller.sol";

import {ComptrollerErrorReporter} from "@protocol/ErrorReporter.sol";
import {MToken} from "@protocol/MToken.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";
import {WhitePaperInterestRateModel} from "@protocol/irm/WhitePaperInterestRateModel.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {SigUtils} from "@test/helper/SigUtils.sol";
import {SimplePriceOracle} from "@test/helper/SimplePriceOracle.sol";
import {MErc20Immutable} from "@test/mock/MErc20Immutable.sol";

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
        bytes memory initdata =
            abi.encodeWithSignature("initialize(address,address)", address(comptroller), address(this));
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(distributor), address(this), initdata);
        /// wire proxy up
        distributor = MultiRewardDistributor(address(proxy));

        comptroller._setRewardDistributor(distributor);
        comptroller._setPriceOracle(oracle);
        comptroller._supportMarket(mToken);
        oracle.setUnderlyingPrice(mToken, 1e18);

        router = new WETHRouter(WETH9(address(weth)), MErc20(address(mToken)));
    }

    function testSetup() public view {
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

    function testMintFailsTokens() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        cToken.setError(true);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));

        vm.deal(address(this), 1 ether);

        vm.expectRevert("WETHRouter: mint failed");
        router.mint{value: 1 ether}(address(this));
    }

    function testRepayBorrowBehalfSucceeds() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));
        acceptEth = true;

        vm.deal(address(this), 1 ether);

        router.repayBorrowBehalf{value: 1 ether}(address(this));

        assertEq(address(this).balance, 0, "this contract balance should be 0");
        assertEq(weth.balanceOf(address(router)), 0, "router weth balance should be 0");
        assertEq(weth.balanceOf(address(cToken)), 1 ether, "mToken weth balance should be 1 ether");
        assertEq(cToken.borrowBalanceRepaid(address(this)), 1 ether, "borrow balance repaid should be 1 ether");
    }

    function testRepayBorrowBehalfTooMuchEthSucceeds() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));
        acceptEth = true;

        vm.deal(address(this), 10 ether);

        router.repayBorrowBehalf{value: 10 ether}(address(this));

        assertEq(address(this).balance, 9 ether, "this contract balance should be 9");
        assertEq(weth.balanceOf(address(router)), 0, "router weth balance should be 0");
        assertEq(weth.balanceOf(address(cToken)), 1 ether, "mToken weth balance should be 1 ether");
        assertEq(cToken.borrowBalanceRepaid(address(this)), 1 ether, "borrow balance repaid should be 1 ether");
    }

    function testRepayBorrowBehalfTooMuchEthSucceedsRepayFails() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));
        cToken.setError(true);
        acceptEth = true;

        vm.deal(address(this), 10 ether);

        vm.expectRevert("WETHRouter: repay borrow behalf failed");
        router.repayBorrowBehalf{value: 10 ether}(address(this));

        assertEq(address(this).balance, 10 ether, "this contract balance should be 10");
    }

    function testRepayBorrowBehalfTooMuchEthRepayFails() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));

        vm.deal(address(this), 10 ether);

        vm.expectRevert("WETHRouter: ETH transfer failed");
        router.repayBorrowBehalf{value: 10 ether}(address(this));

        assertEq(address(this).balance, 10 ether, "this contract balance should be 10");
    }

    function testRepayBorrowBehalfFails() public {
        MockCToken cToken = new MockCToken(IERC20(address(weth)), false);
        router = new WETHRouter(WETH9(address(weth)), MErc20(address(cToken)));

        vm.deal(address(this), 1 ether);

        cToken.setError(true);
        vm.expectRevert("WETHRouter: repay borrow behalf failed");
        router.repayBorrowBehalf{value: 1 ether}(address(this));
    }

    function testSendEtherToWethRouterFails() public {
        vm.deal(address(this), 1 ether);

        vm.expectRevert("WETHRouter: not weth");
        (bool success,) = address(router).call{value: 1 ether}("");
        success;
        /// shhhhh apparently this call succeeds but reverts? go figure

        assertEq(address(this).balance, 1 ether, "incorrect test contract eth value");
        assertEq(address(router).balance, 0, "incorrect router eth value");
    }

    receive() external payable {
        require(acceptEth, "Eth not accepted");
    }
}

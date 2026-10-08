// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {MWethOwnerWrapper} from "@protocol/MWethOwnerWrapper.sol";
import {ComptrollerInterface} from "@protocol/ComptrollerInterface.sol";
import {InterestRateModel} from "@protocol/irm/InterestRateModel.sol";

import {MockWeth} from "@test/mock/MockWeth.sol";
import {MockMToken} from "@test/mock/MockMToken.sol";

contract MWethOwnerWrapperUnitTest is Test {
    MWethOwnerWrapper public wrapper;
    MWethOwnerWrapper public implementation;
    TransparentUpgradeableProxy public proxy;
    ProxyAdmin public proxyAdmin;
    MockWeth public weth;
    MockMToken public mToken;

    address public owner = address(0x1);
    address public notOwner = address(0x2);

    event EthWrapped(uint256 amount);
    event TokenWithdrawn(
        address indexed token,
        address indexed to,
        uint256 amount
    );

    function setUp() public {
        // Deploy mocks
        weth = new MockWeth();
        mToken = new MockMToken();

        // Fund mToken with ETH for testing reserve reductions
        vm.deal(address(mToken), 100 ether);

        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin();

        // Deploy implementation
        implementation = new MWethOwnerWrapper();

        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            MWethOwnerWrapper.initialize.selector,
            address(mToken),
            address(weth),
            owner
        );

        proxy = new TransparentUpgradeableProxy(
            address(implementation),
            address(proxyAdmin),
            initData
        );

        // Wrap proxy in MWethOwnerWrapper interface
        wrapper = MWethOwnerWrapper(payable(address(proxy)));
    }

    // ============================================
    // Initialization Tests
    // ============================================

    function testInitialization() public view {
        assertEq(address(wrapper.mToken()), address(mToken));
        assertEq(address(wrapper.weth()), address(weth));
        assertEq(wrapper.owner(), owner);
    }

    function testCannotInitializeWithZeroMToken() public {
        MWethOwnerWrapper newImpl = new MWethOwnerWrapper();

        bytes memory initData = abi.encodeWithSelector(
            MWethOwnerWrapper.initialize.selector,
            address(0),
            address(weth),
            owner
        );

        vm.expectRevert("MWethOwnerWrapper: mToken cannot be zero address");
        new TransparentUpgradeableProxy(
            address(newImpl),
            address(proxyAdmin),
            initData
        );
    }

    function testCannotInitializeWithZeroWeth() public {
        MWethOwnerWrapper newImpl = new MWethOwnerWrapper();

        bytes memory initData = abi.encodeWithSelector(
            MWethOwnerWrapper.initialize.selector,
            address(mToken),
            address(0),
            owner
        );

        vm.expectRevert("MWethOwnerWrapper: weth cannot be zero address");
        new TransparentUpgradeableProxy(
            address(newImpl),
            address(proxyAdmin),
            initData
        );
    }

    function testCannotInitializeWithZeroOwner() public {
        MWethOwnerWrapper newImpl = new MWethOwnerWrapper();

        bytes memory initData = abi.encodeWithSelector(
            MWethOwnerWrapper.initialize.selector,
            address(mToken),
            address(weth),
            address(0)
        );

        vm.expectRevert("MWethOwnerWrapper: owner cannot be zero address");
        new TransparentUpgradeableProxy(
            address(newImpl),
            address(proxyAdmin),
            initData
        );
    }

    // ============================================
    // Receive ETH and Auto-Wrap Tests
    // ============================================

    function testReceiveEthAutoWraps() public {
        uint256 amount = 1 ether;
        vm.deal(address(this), amount);

        uint256 balanceBefore = weth.balanceOf(address(wrapper));

        vm.expectEmit(true, true, true, true);
        emit EthWrapped(amount);

        (bool success, ) = address(wrapper).call{value: amount}("");
        assertTrue(success);

        uint256 balanceAfter = weth.balanceOf(address(wrapper));
        assertEq(balanceAfter - balanceBefore, amount);
    }

    function testReceiveZeroEthDoesNotEmit() public {
        vm.deal(address(this), 1 ether);

        uint256 wethBalanceBefore = weth.balanceOf(address(wrapper));

        (bool success, ) = address(wrapper).call{value: 0}("");
        assertTrue(success);

        // No WETH should be minted for zero value
        uint256 wethBalanceAfter = weth.balanceOf(address(wrapper));
        assertEq(wethBalanceAfter, wethBalanceBefore);
    }

    // ============================================
    // Admin Function Delegation Tests
    // ============================================

    function testReduceReserves() public {
        uint256 reduceAmount = 10 ether;

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        uint256 initialReserves = mToken.totalReserves();
        uint256 wethBalanceBefore = weth.balanceOf(address(wrapper));

        vm.prank(owner);
        uint256 result = wrapper._reduceReserves(reduceAmount);

        assertEq(result, 0); // success
        assertEq(mToken.totalReserves(), initialReserves - reduceAmount);
        assertEq(mToken.reduceReservesCallCount(), 1);
        assertEq(mToken.lastReduceReservesAmount(), reduceAmount);

        // Check that ETH was received and auto-wrapped
        uint256 wethBalanceAfter = weth.balanceOf(address(wrapper));
        assertEq(wethBalanceAfter - wethBalanceBefore, reduceAmount);
    }

    function testReduceReservesOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._reduceReserves(1 ether);
    }

    function testSetPendingAdmin() public {
        address newPendingAdmin = address(0x123);

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        uint256 result = wrapper._setPendingAdmin(payable(newPendingAdmin));

        assertEq(result, 0); // success
        assertEq(mToken.pendingAdmin(), newPendingAdmin);
    }

    function testSetPendingAdminOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setPendingAdmin(payable(address(0x123)));
    }

    function testAcceptAdmin() public {
        // Set wrapper as pending admin
        mToken._setPendingAdmin(payable(address(wrapper)));

        vm.prank(owner);
        uint256 result = wrapper._acceptAdmin();

        assertEq(result, 0); // success
        assertEq(mToken.admin(), address(wrapper));
        assertEq(mToken.pendingAdmin(), address(0));
    }

    function testAcceptAdminOnlyOwner() public {
        mToken._setPendingAdmin(payable(address(wrapper)));

        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._acceptAdmin();
    }

    function testSetComptroller() public {
        ComptrollerInterface newComptroller = ComptrollerInterface(
            address(0x456)
        );

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        uint256 result = wrapper._setComptroller(newComptroller);

        assertEq(result, 0); // success
        assertEq(address(mToken.comptroller()), address(newComptroller));
    }

    function testSetComptrollerOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setComptroller(ComptrollerInterface(address(0x456)));
    }

    function testSetReserveFactor() public {
        uint256 newReserveFactor = 0.1e18;

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        uint256 result = wrapper._setReserveFactor(newReserveFactor);

        assertEq(result, 0); // success
        assertEq(mToken.reserveFactorMantissa(), newReserveFactor);
    }

    function testSetReserveFactorOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setReserveFactor(0.1e18);
    }

    function testSetInterestRateModel() public {
        InterestRateModel newIRM = InterestRateModel(address(0x789));

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        uint256 result = wrapper._setInterestRateModel(newIRM);

        assertEq(result, 0); // success
        assertEq(address(mToken.interestRateModel()), address(newIRM));
    }

    function testSetInterestRateModelOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setInterestRateModel(InterestRateModel(address(0x789)));
    }

    function testSetProtocolSeizeShare() public {
        uint256 newSeizeShare = 0.05e18;

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        uint256 result = wrapper._setProtocolSeizeShare(newSeizeShare);

        assertEq(result, 0); // success
        assertEq(mToken.protocolSeizeShareMantissa(), newSeizeShare);
    }

    function testSetProtocolSeizeShareOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setProtocolSeizeShare(0.05e18);
    }

    function testAddReserves() public {
        uint256 addAmount = 5 ether;

        // First, transfer admin of mToken to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        // Fund wrapper with WETH
        vm.deal(address(this), addAmount);
        weth.deposit{value: addAmount}();
        weth.transfer(address(wrapper), addAmount);

        uint256 initialReserves = mToken.totalReserves();

        vm.prank(owner);
        uint256 result = wrapper._addReserves(addAmount);

        assertEq(result, 0); // success
        assertEq(mToken.totalReserves(), initialReserves + addAmount);
        assertEq(mToken.addReservesCallCount(), 1);
        assertEq(mToken.lastAddReservesAmount(), addAmount);
    }

    function testAddReservesOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._addReserves(1 ether);
    }

    // ============================================
    // Token Withdrawal Tests
    // ============================================

    function testSetImplementation() public {
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        address newImplementation = address(0xBEEF);

        vm.prank(owner);
        wrapper._setImplementation(newImplementation, true, hex"1234");

        assertEq(mToken.implementation(), newImplementation);
        assertTrue(mToken.lastAllowResign());
        assertEq(mToken.lastBecomeImplementationData(), hex"1234");
    }

    function testSetImplementationOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._setImplementation(address(0xBEEF), true, "");
    }

    function testSweepExcessCash() public {
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        wrapper._sweepExcessCash();

        assertEq(mToken.sweepExcessCashCallCount(), 1);
    }

    function testSweepExcessCashOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._sweepExcessCash();
    }

    function testSyncCashDown() public {
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        vm.prank(owner);
        wrapper._syncCashDown();

        assertEq(mToken.syncCashDownCallCount(), 1);
    }

    function testSyncCashDownOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper._syncCashDown();
    }

    function testWithdrawToken() public {
        uint256 amount = 10 ether;
        address recipient = address(0xabc);

        // Fund wrapper with WETH
        vm.deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.transfer(address(wrapper), amount);

        uint256 recipientBalanceBefore = weth.balanceOf(recipient);

        vm.expectEmit(true, true, true, true);
        emit TokenWithdrawn(address(weth), recipient, amount);

        vm.prank(owner);
        wrapper.withdrawToken(address(weth), recipient, amount);

        uint256 recipientBalanceAfter = weth.balanceOf(recipient);
        assertEq(recipientBalanceAfter - recipientBalanceBefore, amount);
    }

    function testWithdrawTokenOnlyOwner() public {
        vm.prank(notOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        wrapper.withdrawToken(address(weth), address(0xabc), 1 ether);
    }

    function testWithdrawTokenRevertsOnZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert("MWethOwnerWrapper: cannot withdraw to zero address");
        wrapper.withdrawToken(address(weth), address(0), 1 ether);
    }

    function testWithdrawTokenRevertsOnZeroAmount() public {
        vm.prank(owner);
        vm.expectRevert("MWethOwnerWrapper: amount must be greater than zero");
        wrapper.withdrawToken(address(weth), address(0xabc), 0);
    }

    // ============================================
    // View Function Tests
    // ============================================

    function testGetTokenBalance() public {
        uint256 amount = 5 ether;

        // Fund wrapper with WETH
        vm.deal(address(this), amount);
        weth.deposit{value: amount}();
        weth.transfer(address(wrapper), amount);

        assertEq(wrapper.getTokenBalance(address(weth)), amount);
    }

    // ============================================
    // Integration Test: Full Reserve Reduction Flow
    // ============================================

    function testFullReserveReductionFlow() public {
        uint256 reduceAmount = 20 ether;
        address destination = address(0xdead);

        // Step 1: Transfer mToken admin to wrapper
        mToken._setPendingAdmin(payable(address(wrapper)));
        vm.prank(address(wrapper));
        mToken._acceptAdmin();

        assertEq(mToken.admin(), address(wrapper));

        // Step 2: Reduce reserves (wrapper receives ETH and auto-wraps)
        uint256 initialReserves = mToken.totalReserves();

        vm.prank(owner);
        wrapper._reduceReserves(reduceAmount);

        assertEq(mToken.totalReserves(), initialReserves - reduceAmount);
        assertEq(weth.balanceOf(address(wrapper)), reduceAmount);

        // Step 3: Withdraw WETH to destination
        vm.prank(owner);
        wrapper.withdrawToken(address(weth), destination, reduceAmount);

        assertEq(weth.balanceOf(destination), reduceAmount);
        assertEq(weth.balanceOf(address(wrapper)), 0);
    }
}

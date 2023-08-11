pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockWeth} from "@test/mock/MockWeth.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";

contract WethUnwrapperUnitTest is Test {
    WethUnwrapper unwrapper;
    bool acceptEth;
    MockWeth weth;

    function setUp() public {
        weth = new MockWeth();
        unwrapper = new WethUnwrapper(address(weth));
        acceptEth = true;
    }

    function testWethUnwrapFailsNotMToken() public {
        vm.expectRevert("only mToken can call send");
        unwrapper.send(payable(address(0)), 0);
    }

    function testWethUnwrapSucceedsMToken() public {
        uint256 mintAmount = 1 ether;
        weth.deposit{value: mintAmount}();
        weth.transfer(address(unwrapper), mintAmount);

        vm.prank(unwrapper.mToken());
        unwrapper.send(payable(address(this)), mintAmount);
    }

    function testWethUnwrapFailMTokenNotAcceptingDeposits() public {
        uint256 mintAmount = 1 ether;
        weth.deposit{value: mintAmount}();
        weth.transfer(address(unwrapper), mintAmount);

        acceptEth = false;
        vm.prank(unwrapper.mToken());
        vm.expectRevert("not accepting eth");
        unwrapper.send(payable(address(this)), mintAmount);
    }

    receive() external payable {
        require(acceptEth, "not accepting eth");
    }
}

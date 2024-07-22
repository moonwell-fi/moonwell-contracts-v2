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

    function testSetup() public view {
        assertEq(unwrapper.weth(), address(weth));
    }

    function testWethUnwrapSucceedsMToken() public {
        uint256 mintAmount = 1 ether;
        weth.deposit{value: mintAmount}();
        weth.transfer(address(unwrapper), mintAmount);

        unwrapper.send(payable(address(this)), mintAmount);
    }

    function testWethUnwrapFailMTokenNotAcceptingDeposits() public {
        uint256 mintAmount = 1 ether;
        weth.deposit{value: mintAmount}();
        weth.transfer(address(unwrapper), mintAmount);

        acceptEth = false;
        vm.expectRevert("not accepting eth");
        unwrapper.send(payable(address(this)), mintAmount);
    }

    function testSendRawEthToWethUnwrapperFails() public {
        vm.deal(address(this), 1 ether);
        vm.expectRevert("not accepting eth");
        (bool success, ) = address(unwrapper).call{value: 1 ether}("");
        assertEq(success, true); /// idk why this is true, but it is even though it reverts
    }

    receive() external payable {
        require(acceptEth, "not accepting eth");
    }
}

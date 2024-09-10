pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockERC20} from "@test/mock/MockERC20.sol";
import {MarketAddChecker} from "@protocol/governance/MarketAddChecker.sol";

contract MarketAddCheckerUnitTest is Test {
    MarketAddChecker checker;
    MockERC20 well;

    function setUp() public {
        checker = new MarketAddChecker();
        well = new MockERC20();
    }

    function testSetup() public view {
        assertEq(well.totalSupply(), 0, "total supply not zero");
        assertEq(well.balanceOf(address(0)), 0, "balance not zero");
    }

    function testCheckMarketAddRevertsEmpty() public {
        vm.expectRevert("Total supply lt 100 wei");
        checker.checkMarketAdd(address(well));

        well.mint(address(this), 99);

        vm.expectRevert("Total supply lt 100 wei");
        checker.checkMarketAdd(address(well));
    }

    function testCheckMarketAddRevertsNoTokensBurnt() public {
        well.mint(address(this), 100);
        vm.expectRevert("No balance burnt");
        checker.checkMarketAdd(address(well));
    }

    function testCheckMarketAddSucceeds100WeiTokensBurnt() public {
        well.mint(address(this), 99);
        deal(address(well), address(0), 1, true);

        checker.checkMarketAdd(address(well));
    }
}

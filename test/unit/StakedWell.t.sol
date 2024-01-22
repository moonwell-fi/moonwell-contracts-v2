pragma solidity 0.8.19

import "@forge-std/Test.sol";
import "@test/helper/BaseTest.t.sol";

contract StakedWellUnitTest is BaseTest {
    StakedWell stakedWell;

    function setUp() public {
        super.setUp();
        stakedWell = new StakedWell();
        uint256 cooldownPeriod = 1 days;
        uint256 unstakePeriod = 3 days;
        
        stakedWell.initialize(xWELL, xWELL, cooldown, unstakePeriod);
        
    }
}

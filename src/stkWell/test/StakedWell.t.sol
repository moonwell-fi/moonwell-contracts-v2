pragma solidity 0.8.19

import "@forge-std/Test.sol";

contract StakedWellUnitTest {
    StakedWell stakedWell;

    function setUp() public {
        stakedWell = new StakedWell();
        stakedWell.initialize()
        
    }
}

pragma solidity 0.8.19;

import "@forge-std/Test.sol";
contract StakedWellUnitTest is Test {
    function setUp() public {
        address stakedWell = deployCode(
            "StakedWell",
            "stkWell/src/StakedWell.sol"
        );
    }
}

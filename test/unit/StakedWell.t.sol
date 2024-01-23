pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@test/helper/BaseTest.t.sol";

interface IStakedWell {
    function initialize(
        address _stakedToken,
        address _rewardToken,
        uint256 _cooldownPeriod,
        uint256 _unstakePeriod,
        address _rewardsVault,
        address _emissionManager,
        uint128 _distributionDuration,
        address _governance
    ) external;
}

contract StakedWellUnitTest is BaseTest {
    IStakedWell stakedWell;
    uint256 cooldown;
    uint256 unstakePeriod;
    uint256 amount;
    function setUp() public override {
        super.setUp();
        address stakedWellAddress = deployCode(
            "StakedWell.sol:StakedWell",
            "stkWell/artifacts/StakedWell.sol/StakedWell.json"
        );
        stakedWell = IStakedWell(stakedWellAddress);

        cooldown = 1 days;
        unstakePeriod = 3 days;

        stakedWell.initialize(
            address(xwellProxy),
            address(xwellProxy),
            cooldown,
            unstakePeriod,
            address(this),
            address(this),
            1,
            address(this)
        );

        amount = 10_000 ** 10 * 18;
        vm.prank(address(xerc20Lockbox));
        xwellProxy.mint(address(this), amount);
    }

    function testStake() public {
        uint256 balance = xwellProxy.balanceOf(address(this));
        console.log(balance);
    }
}

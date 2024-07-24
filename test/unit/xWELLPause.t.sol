pragma solidity 0.8.19;

import "@test/helper/BaseTest.t.sol";

contract xWELLPauseUnitTest is BaseTest {
    function setUp() public override {
        super.setUp();

        vm.warp(block.timestamp + 1000000);
    }

    /// @notice ACL tests that ensure pause/unpause can only be called by the pause guardian
    function testPauseNonGuardianFails() public {
        vm.expectRevert("ConfigurablePauseGuardian: only pause guardian");
        xwellProxy.pause();
    }

    function testUnpauseNonGuardianFails() public {
        testGuardianCanPause();

        vm.expectRevert("ConfigurablePauseGuardian: only pause guardian");
        xwellProxy.unpause();
    }

    function testKickFailsWithZeroStartTime() public {
        vm.expectRevert(
            "ConfigurablePauseGuardian: did not pause, so cannot kick"
        );
        xwellProxy.kickGuardian();
    }

    function testGuardianCanPause() public {
        assertFalse(xwellProxy.paused(), "should start unpaused");

        vm.prank(pauseGuardian);
        xwellProxy.pause();

        assertTrue(xwellProxy.pauseUsed(), "pause should be used");
        assertTrue(xwellProxy.paused(), "should be paused");
        assertEq(
            xwellProxy.pauseStartTime(),
            block.timestamp,
            "pauseStartTime incorrect"
        );
    }

    function testGuardianCanUnpause() public {
        testGuardianCanPause();

        vm.prank(pauseGuardian);
        xwellProxy.unpause();

        assertFalse(xwellProxy.paused(), "should be unpaused");
        assertEq(xwellProxy.pauseStartTime(), 0, "pauseStartTime incorrect");
        assertFalse(xwellProxy.pauseUsed(), "pause should be used");
        assertEq(
            xwellProxy.pauseGuardian(),
            address(0),
            "pause guardian incorrect"
        );
    }

    function testShouldUnpauseAutomaticallyAfterPauseDuration() public {
        testGuardianCanPause();

        vm.warp(pauseDuration + block.timestamp);
        assertTrue(xwellProxy.paused(), "should still be paused");

        vm.warp(block.timestamp + 1);
        assertFalse(xwellProxy.paused(), "should be unpaused");
    }

    function testPauseFailsPauseAlreadyUsed() public {
        testShouldUnpauseAutomaticallyAfterPauseDuration();

        vm.prank(pauseGuardian);
        vm.expectRevert("ConfigurablePauseGuardian: pause already used");
        xwellProxy.pause();
    }

    function testCanKickGuardianAfterPauseUsed() public {
        testShouldUnpauseAutomaticallyAfterPauseDuration();

        xwellProxy.kickGuardian();

        assertEq(
            xwellProxy.pauseGuardian(),
            address(0),
            "incorrect pause guardian"
        );
        assertEq(xwellProxy.pauseStartTime(), 0, "pauseStartTime incorrect");
        assertFalse(xwellProxy.pauseUsed(), "incorrect pause used");
    }

    function testKickGuardianSucceedsAfterUnpause() public {
        testGuardianCanPause();

        vm.warp(pauseDuration + block.timestamp);
        assertTrue(xwellProxy.paused(), "should still be paused");

        vm.prank(pauseGuardian);
        xwellProxy.unpause();
        assertFalse(xwellProxy.paused(), "should be unpaused");
        assertEq(xwellProxy.pauseStartTime(), 0, "pauseStartTime incorrect");

        /// in this scenario, kickGuardian fails because the pause
        /// guardian is address(0), and the pauseStartTime is 0,
        /// this means the contract is unpaused, so
        vm.expectRevert(
            "ConfigurablePauseGuardian: did not pause, so cannot kick"
        );
        xwellProxy.kickGuardian();
    }
}

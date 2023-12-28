import "helpers.spec";
import "IERC20.spec";
import "IERC2612.spec";
import "IPauseable.spec";

function timestampMax() returns uint256 {
    return 2 ^ 128 - 1;
}

function uintMax() returns uint256 {
    return 2 ^ 256 - 1;
}

/// Preconditions:
///    - block timestamp is under or equal uint32 max and gt 0

/// Invariants:
///     1. paused, pauseStartTime != 0, guardian != address(0)
///     2. unpaused, pauseStartTime == 0, guardian == address(0)
///     3. unpaused, pauseStartTime <= block.timestamp - pauseDuration, guardian != address(0)
///     4. unpaused after kick, pauseStartTime == 0, guardian == address(0)
/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Ghost: all state variables                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
ghost address pauseGuardian {
    init_state axiom pauseGuardian == 0;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Hooks: all state variables                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/

/// @title The hook for writing to pause guardian
hook Sstore pauseGuardian address newPauseGuardian (address oldPauseGuardian) STORAGE
{
    pauseGuardian = newPauseGuardian;
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Invariants                                                                                                          │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/

invariant pauseGuardianMirrorCorrect()
    pauseGuardian == pauseGuardian();

invariant pauseDurationLteMax()
    assert_uint256(pauseDuration()) <= maxPauseDuration();

invariant pausedCorrect(env e)
    paused(e) => (
        to_mathint(e.block.timestamp) >= to_mathint(pauseStartTime()) &&
        to_mathint(e.block.timestamp) <= pauseStartTime() + pauseDuration()
    ) {
        preserved {
            require timestampMax() >= e.block.timestamp;
            requireInvariant pauseDurationLteMax();
            requireInvariant pauseGuardianMirrorCorrect();
        } preserved pause() with (env e1) {
            require e1.block.timestamp == e.block.timestamp;
            require timestampMax() >= e1.block.timestamp;
            requireInvariant pausedCorrect(e1);
            requireInvariant pauseDurationLteMax();
            requireInvariant pauseGuardianMirrorCorrect();
        }
    }

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: kick behavior and side effects                                                                                │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule kickSucceeds(env e) {
   require pauseUsed(e);
   require !paused(e);
   require pauseGuardian != 0;

   address guardianStartingAddress = pauseGuardian;

   kickGuardian(e);
   
   assert !paused(e), "not unpaused";
   assert pauseGuardian == 0, "pause guardian address 0";
   assert pauseStartTime() == 0, "pause start time not reset";
   assert guardianStartingAddress != 0, "guardianStartingAddress eq 0 address";
}

/*
┌─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
│ Rule: pause/unpause behavior and side effects                                                                       │
└─────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
*/
rule pauseSucceeds(env e) {
   /// constrain the prover to a sane block timestamp we will see in this lifetime
   require e.block.timestamp > 0 && e.block.timestamp <= timestampMax();
   require !pauseUsed(e);
   require !paused(e);
   require pauseGuardian != 0;

   address guardianStartingAddress = pauseGuardian;

   pause(e);
   
   assert paused(e), "not paused";
   assert pauseUsed(e) == true, "pause used";
   assert pauseGuardian == guardianStartingAddress, "pause guardian address 0";
   assert to_mathint(pauseStartTime()) == to_mathint(e.block.timestamp), "pause start time not set";
}

rule unpauseSucceeds(env e) {
   /// constrain the prover to a sane block timestamp we will see in this lifetime
   require e.block.timestamp > 0 && e.block.timestamp <= timestampMax();
   require pauseUsed(e);
   require paused(e);
   require pauseGuardian != 0;

   address guardianStartingAddress = pauseGuardian;

   unpause(e);
   
   assert !paused(e), "not paused";
   assert !pauseUsed(e) == true, "pause should not be used";
   assert pauseStartTime() == 0, "pause start time not reset";
   assert pauseGuardian == 0, "pause guardian not kicked";
   assert guardianStartingAddress != 0, "pause start time not reset";
}

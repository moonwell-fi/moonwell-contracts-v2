methods {
    function pauseStartTime()                      external returns (uint128) envfree;
    function maxPauseDuration()                    external returns (uint256) envfree;
    function pauseDuration()                       external returns (uint128) envfree;
    function pauseGuardian()                       external returns (address) envfree;
    function paused()                              external returns (bool)           ;
}

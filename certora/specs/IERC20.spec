methods {
    function name()                                external returns (string)  envfree;
    function symbol()                              external returns (string)  envfree;
    function decimals()                            external returns (uint8)   envfree;
    function totalSupply()                         external returns (uint256) envfree;
    function maxSupply()                           external returns (uint256) envfree;
    function MAX_SUPPLY()                          external returns (uint256) envfree;
    function balanceOf(address)                    external returns (uint256) envfree;
    function allowance(address,address)            external returns (uint256) envfree;
    function approve(address,uint256)              external returns (bool)           ;
    function transfer(address,uint256)             external returns (bool)           ;
    function transferFrom(address,address,uint256) external returns (bool)           ;
    function paused()                              external returns (bool)           ;
    function buffer(address)                       external returns (uint256)        ;
    function getPastTotalSupply(uint256)           external returns (uint256)        ;
    function numCheckpoints(address)               external returns (uint32)  envfree;
    function delegates(address)                    external returns (address) envfree;
    function bufferCap(address)                    external returns (uint256) envfree;
    function getVotes(address)                     external returns (uint256) envfree;
    function rateLimitPerSecond(address)           external returns (uint256) envfree;
    function minBufferCap()                        external returns (uint112) envfree;
    function maxRateLimitPerSecond()               external returns (uint128) envfree;
}

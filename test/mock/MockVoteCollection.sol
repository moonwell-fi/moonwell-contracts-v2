pragma solidity 0.8.19;

import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";

contract MockVoteCollection is MultichainVoteCollection {
    constructor(
        address _coreBridge,
        address _executor,
        address _executorQuoterRouter
    ) MultichainVoteCollection(_coreBridge, _executor, _executorQuoterRouter) {}
    function newFeature() external pure returns (uint256) {
        return 1;
    }
}

pragma solidity 0.8.19;

import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";

contract MockVoteCollection is MultichainVoteCollection {
    function newFeature() external pure returns (uint256) {
        return 1;
    }
}

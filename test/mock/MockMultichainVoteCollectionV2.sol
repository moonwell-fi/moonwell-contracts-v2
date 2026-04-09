pragma solidity 0.8.19;

import {MultichainVoteCollectionV2} from "@protocol/governance/multichain/MultichainVoteCollectionV2.sol";

contract MockMultichainVoteCollectionV2 is MultichainVoteCollectionV2 {
    function newFeature() external pure returns (uint256) {
        return 1;
    }
}

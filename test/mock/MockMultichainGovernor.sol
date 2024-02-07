pragma solidity 0.8.19;

import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";

contract MockMultichainGovernor is MultichainGovernor {
    function newFeature() external pure returns (uint256) {
        return 1;
    }
}

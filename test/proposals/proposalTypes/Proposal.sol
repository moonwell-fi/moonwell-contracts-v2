pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {IProposal} from "@test/proposals/proposalTypes/IProposal.sol";

abstract contract Proposal is IProposal, Test {
    bool public DEBUG = true;

    function setDebug(bool value) external {
        DEBUG = value;
    }
}

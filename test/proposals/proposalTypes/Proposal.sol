pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {IProposal} from "@test/proposals/proposalTypes/IProposal.sol";
import {MIPProposal} from "@test/proposals/MIPProposal.s.sol";

abstract contract Proposal is Test, MIPProposal {
    bool public DEBUG = true;

    function setDebug(bool value) external {
        DEBUG = value;
    }
}

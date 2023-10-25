pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";

abstract contract Proposal is Test, MIPProposal {}

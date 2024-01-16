pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {MoonwellArtemisGovernor, TimelockInterface} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

abstract contract GovernanceProposal is Proposal {
    bool private DEBUG;

    struct GovernanceAction {
        address target;
        uint value;
        string signature;
        bytes data;
    }

    GovernanceAction[] public actions;

    /// @notice set the debug flag
    function setDebug(bool debug) public {
        DEBUG = debug;
    }
 
    /// @notice deal tokens
    /// @param token address of the token
    /// @param toAddress address to send tokens to
    /// @param amount amount to deal
    function _deal(address token, address toAddress, uint256 amount) internal {
        deal(token, toAddress, amount, false);
    }

    /// @notice delegate voting power
    /// @param proposerAddress address of the proposer
    /// @param token token
    function _delegate(address proposerAddress, Well token) internal {
        token.delegate(proposerAddress);
    }

    /// @notice push a Governance proposal action
    /// @param target the target contract
    /// @param value msg.value
    /// @param signature function signature
    /// @param data calldata
    function _pushGovernanceAction(address target, uint value, string memory signature, bytes memory data) internal {
        actions.push(GovernanceAction({target: target, value: value, signature: signature, data: data}));
    }

    /// @notice push an action to the Governance proposal with a value of 0
    /// @param target the target contract
    /// @param signature function signature
    /// @param data calldata
    function _pushGovernanceAction(address target, string memory signature, bytes memory data) internal {
        _pushGovernanceAction(target, 0, signature, data);
    }

    /// @notice Simulate governance proposal
    /// @param timelockAddress address of the timelock
    /// @param governorAddress address of the artemis governor
    /// @param proposerAddress address of the proposer
    function _simulateGovernanceActions(
        address timelockAddress,
        address governorAddress, 
        address proposerAddress,
        string memory description)
    internal {
        require(actions.length > 0, "Empty governance operation");

        /// @dev skip ahead
        vm.roll(block.number + 1000);

        /// @dev loop through the struct and prep the data for the governance proposal
        address[] memory targets = new address[](actions.length);
        uint256[] memory values = new uint256[](actions.length);
        string[] memory signatures = new string[](actions.length);
        bytes[] memory calldatas = new bytes[](actions.length);
        for (uint i = 0; i < actions.length; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            signatures[i] = actions[i].signature;
            calldatas[i] = actions[i].data;
        }

        MoonwellArtemisGovernor governor = MoonwellArtemisGovernor(governorAddress);
        uint proposalId = governor.propose(
            targets,
            values,
            signatures,
            calldatas,
            description
        );

        /// @dev warp past the voting delay
        vm.warp(block.timestamp + governor.votingDelay() + 1);

        /// @dev vote yes on said proposal
        governor.castVote(proposalId, 0);

        /// @dev warp past voting end time
        vm.warp(block.timestamp + governor.votingPeriod());

        /// @dev queue the proposal
        governor.queue(proposalId);

        TimelockInterface timelock = TimelockInterface(payable(timelockAddress));
        vm.warp(block.timestamp + timelock.delay());

        /// @dev execute the proposal
        governor.execute(proposalId);
        vm.roll(block.number + 1);
    }
}

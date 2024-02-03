pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {Well} from "@protocol/Governance/deprecated/Well.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {MoonwellArtemisGovernor, TimelockInterface} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";

abstract contract GovernanceProposal is Proposal {
    bool private DEBUG;

    struct GovernanceAction {
        address target;
        uint256 value;
        string description;
        bytes data;
    }

    GovernanceAction[] public actions;

    /// @notice hex encoded description of the proposal
    bytes public PROPOSAL_DESCRIPTION;

    /// @notice set the governance proposal's description
    function _setProposalDescription(
        bytes memory newProposalDescription
    ) internal {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

    /// @notice set the debug flag
    function setDebug(bool debug) public {
        DEBUG = debug;
    }

    /// @notice get actions
    function _getActions()
        internal
        view
        returns (
            address[] memory,
            uint256[] memory,
            string[] memory,
            bytes[] memory
        )
    {
        uint256 actionsLength = actions.length;
        address[] memory targets = new address[](actionsLength);
        uint256[] memory values = new uint256[](actionsLength);
        string[] memory signatures = new string[](actionsLength);
        bytes[] memory calldatas = new bytes[](actionsLength);

        for (uint256 i = 0; i < actionsLength; i++) {
            targets[i] = actions[i].target;
            values[i] = actions[i].value;
            signatures[i] = "";
            calldatas[i] = actions[i].data;
        }

        return (targets, values, signatures, calldatas);
    }

    /// @notice print the actions that will be executed by the proposal
    function printActions(address) public {
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = _getActions();

        bytes memory governorCalldata = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            targets,
            values,
            signatures,
            calldatas,
            PROPOSAL_DESCRIPTION
        );

        console.log("governor calldata");
        emit log_bytes(governorCalldata);
    }

    /// @notice print calldata
    function printCalldata(Addresses addresses) public override {
        printActions(addresses.getAddress("ARTEMIS_GOVERNOR"));
    }

    /// @notice print the proposal action steps
    function printProposalActionSteps() public override {
        console.log(
            "\n\nProposal Description:\n\n%s",
            string(PROPOSAL_DESCRIPTION)
        );

        console.log(
            "\n\n------------------ Proposal Actions ------------------"
        );

        for (uint256 i = 0; i < actions.length; i++) {
            console.log("%d). %s", i + 1, actions[i].description);
            console.log(
                "target: %s\nvalue: %d\npayload",
                actions[i].target,
                actions[i].value
            );
            emit log_bytes(actions[i].data);

            console.log("\n");
        }
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
    /// @param description description of the action
    /// @param data calldata
    function _pushGovernanceAction(
        address target,
        uint256 value,
        string memory description,
        bytes memory data
    ) internal {
        actions.push(
            GovernanceAction({
                target: target,
                value: value,
                description: description,
                data: data
            })
        );
    }

    /// @notice push an action to the Governance proposal with a value of 0
    /// @param target the target contract
    /// @param description description of the action
    /// @param data calldata
    function _pushGovernanceAction(
        address target,
        string memory description,
        bytes memory data
    ) internal {
        _pushGovernanceAction(target, 0, description, data);
    }

    /// @notice Simulate governance proposal
    /// @param timelockAddress address of the timelock
    /// @param governorAddress address of the artemis governor
    /// @param proposerAddress address of the proposer
    function _simulateGovernanceActions(
        address timelockAddress,
        address governorAddress,
        address
    ) internal {
        uint256 actionsLength = actions.length;
        require(actionsLength > 0, "Empty governance operation");

        /// @dev deal and delegate, so the proposal can be simulated end-to-end
        Addresses addresses = new Addresses();
        Well well = Well(payable(addresses.getAddress("WELL")));
        _deal(address(well), address(this), 100_000_000e18);
        _delegate(address(this), well);

        /// @dev skip ahead
        vm.roll(block.number + 1000);

        /// @dev build proposal
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = _getActions();
        MoonwellArtemisGovernor governor = MoonwellArtemisGovernor(
            governorAddress
        );
        bytes memory encoded = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            targets,
            values,
            signatures,
            calldatas,
            PROPOSAL_DESCRIPTION
        );

        /// @dev output
        if (DEBUG) {
            console.log(
                "Governance proposal with",
                actionsLength,
                (actionsLength > 1 ? "actions." : "action.")
            );
            emit log_bytes(encoded);
        }

        (bool success, bytes memory data) = address(governor).call{value: 0}(
            encoded
        );
        require(
            success,
            "GovernanceProposal: failed to raise governance proposal"
        );

        uint256 proposalId = abi.decode(data, (uint256));
        {
            /// @dev check that the proposal is in the pending state
            MoonwellArtemisGovernor.ProposalState proposalState = governor
                .state(proposalId);
            require(
                proposalState == MoonwellArtemisGovernor.ProposalState.Pending
            );

            /// @dev warp past the voting delay
            vm.warp(block.timestamp + governor.votingDelay() + 1);
        }

        {
            /// @dev vote yes on said proposal
            governor.castVote(proposalId, 0);

            /// @dev warp past voting end time
            vm.warp(block.timestamp + governor.votingPeriod());

            /// @dev queue the proposal
            governor.queue(proposalId);

            TimelockInterface timelock = TimelockInterface(
                payable(timelockAddress)
            );
            vm.warp(block.timestamp + timelock.delay());

            /// @dev execute the proposal
            governor.execute(proposalId);
            vm.roll(block.number + 1);
        }
    }
}

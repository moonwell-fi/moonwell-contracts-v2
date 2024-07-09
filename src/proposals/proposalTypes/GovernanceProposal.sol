pragma solidity 0.8.19;

import {ERC20Votes} from
    "@openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Votes.sol";

import {console} from "@forge-std/console.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {MultichainGovernor} from
    "@protocol/governance/multichain/MultichainGovernor.sol";
import {IArtemisGovernor as MoonwellArtemisGovernor} from
    "@protocol/interfaces/IArtemisGovernor.sol";
import {ITimelock} from "@protocol/interfaces/ITimelock.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";

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
    function _setProposalDescription(bytes memory newProposalDescription)
        internal
    {
        PROPOSAL_DESCRIPTION = newProposalDescription;
    }

    /// @notice set the debug flag
    function setDebug(bool debug) public {
        DEBUG = debug;
    }

    /// @notice get actions
    function _getActions()
        public
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
    function printActions() public {
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
    function printCalldata(Addresses) public override {
        printActions();
    }

    /// @notice search for a on-chain proposal that matches the proposal calldata
    /// @return proposalId 0 if no proposal is found
    function getProposalId(Addresses, address governor)
        public
        override
        returns (uint256 proposalId)
    {
        vm.selectFork(MOONBEAM_FORK_ID);

        MoonwellArtemisGovernor governorContract =
            MoonwellArtemisGovernor(governor);
        uint256 proposalCount = onchainProposalId != 0
            ? onchainProposalId
            : MultichainGovernor(governor).proposalCount();

        (
            address[] memory proposalTargets,
            uint256[] memory proposalValues,
            string[] memory proposalSignatures,
            bytes[] memory proposalCalldatas
        ) = _getActions();

        bytes memory governorCalldata = abi.encodeWithSignature(
            "propose(address[],uint256[],string[],bytes[],string)",
            proposalTargets,
            proposalValues,
            proposalSignatures,
            proposalCalldatas,
            PROPOSAL_DESCRIPTION
        );

        while (proposalCount > 0) {
            (
                address[] memory onchainTargets,
                uint256[] memory onchainValues,
                string[] memory onchainSignatures,
                bytes[] memory onchainCalldatas
            ) = governorContract.getActions(proposalCount);

            bytes memory onchainCalldata = abi.encodeWithSignature(
                "propose(address[],uint256[],string[],bytes[],string)",
                onchainTargets,
                onchainValues,
                onchainSignatures,
                onchainCalldatas,
                PROPOSAL_DESCRIPTION
            );

            if (keccak256(governorCalldata) == keccak256(onchainCalldata)) {
                proposalId = proposalCount;
                break;
            }

            proposalCount--;
        }

        vm.selectFork(uint256(primaryForkId()));
    }

    /// @notice print the proposal action steps
    function printProposalActionSteps() public override {
        console.log(
            "\n\nProposal Description:\n\n%s", string(PROPOSAL_DESCRIPTION)
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
    function _delegate(address proposerAddress, ERC20Votes token) internal {
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
        address proposerAddress
    ) internal {
        uint256 actionsLength = actions.length;
        require(actionsLength > 0, "Empty governance operation");

        /// @dev deal and delegate, so the proposal can be simulated end-to-end
        Addresses addresses = new Addresses();
        address well = payable(addresses.getAddress("GOVTOKEN"));
        _deal(well, proposerAddress, 100_000_000e18);
        _delegate(proposerAddress, ERC20Votes(well));

        /// @dev skip ahead
        vm.roll(block.number + 1000);

        /// @dev build proposal
        (
            address[] memory targets,
            uint256[] memory values,
            string[] memory signatures,
            bytes[] memory calldatas
        ) = _getActions();
        MoonwellArtemisGovernor governor =
            MoonwellArtemisGovernor(governorAddress);
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

        vm.prank(proposerAddress);
        (bool success, bytes memory data) =
            address(governor).call{value: 0}(encoded);
        require(
            success, "GovernanceProposal: failed to raise governance proposal"
        );

        uint256 proposalId = abi.decode(data, (uint256));
        {
            /// @dev check that the proposal is in the pending state
            MoonwellArtemisGovernor.ProposalState proposalState =
                governor.state(proposalId);
            require(
                proposalState == MoonwellArtemisGovernor.ProposalState.Pending
            );

            /// @dev warp past the voting delay
            vm.warp(block.timestamp + governor.votingDelay() + 1);
        }

        {
            /// @dev vote yes on said proposal
            vm.prank(proposerAddress);
            governor.castVote(proposalId, 0);

            /// @dev warp past voting end time
            vm.warp(block.timestamp + governor.votingPeriod());

            /// @dev queue the proposal
            governor.queue(proposalId);

            ITimelock timelock = ITimelock(payable(timelockAddress));
            vm.warp(block.timestamp + timelock.delay());

            /// @dev execute the proposal
            governor.execute(proposalId);
            vm.roll(block.number + 1);
        }
    }
}

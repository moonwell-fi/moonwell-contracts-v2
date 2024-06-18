pragma solidity 0.8.19;

import {Proposal} from "@proposals/proposalTypes/Proposal.sol";

abstract contract MultisigProposal is Proposal {
    ProposalAction[] public actions;

    /// @notice push an action to the Multisig proposal
    function _pushMultisigAction(
        uint256 value,
        address target,
        bytes memory data,
        string memory description
    ) internal {
        actions.push(
            ProposalAction({
                value: value,
                target: target,
                data: data,
                description: description
            })
        );
    }

    /// @notice push an action to the Multisig proposal with a value of 0
    function _pushMultisigAction(
        address target,
        bytes memory data,
        string memory description
    ) internal {
        _pushMultisigAction(0, target, data, description);
    }

    /// @notice simulate multisig proposal
    /// @param multisigAddress address of the multisig doing the calls
    function _simulateMultisigActions(address multisigAddress) internal {
        vm.startPrank(multisigAddress);

        for (uint256 i = 0; i < actions.length; i++) {
            (bool success, bytes memory result) = actions[i].target.call{
                value: actions[i].value
            }(actions[i].data);

            require(success, string(result));
        }

        vm.stopPrank();
    }
}

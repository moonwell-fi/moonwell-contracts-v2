pragma solidity 0.8.19;

/// @notice this is a proposal type to be used for proposals that
/// require actions to be taken on both moonbeam and base.
/// This is a bit wonky because we are trying to simulate
/// what happens on two different networks. So we need to have
/// two different proposal types. One for moonbeam and one for base.
/// We also need to have references to both networks in the proposal
/// to switch between forks.
interface IHybridProposal {
    struct ProposalAction {
        /// address to call
        address target;
        /// value to send
        uint256 value;
        /// calldata to pass to the target
        bytes data;
        /// for human description
        string description;
    }
}

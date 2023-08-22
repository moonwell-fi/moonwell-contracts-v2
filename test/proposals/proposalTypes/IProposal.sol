pragma solidity 0.8.19;

import {Addresses} from "@test/proposals/Addresses.sol";

interface IProposal {
    // Proposal name, e.g. "ZIP16"
    function name() external view returns (string memory);

    // Used to explicitly enable or disable debug logs from
    // another solidity file that calls this proposal.
    function setDebug(bool) external;

    // Deploy contracts and add them to list of addresses
    function deploy(Addresses, address) external;

    // After deploying, call initializers and link contracts
    // together, e.g. if you deployed Core and Volt contracts,
    // you could link them in this step by calling core.setVolt(volt).
    function afterDeploy(Addresses, address) external;

    // After deploying, do setup for a testnet,
    // e.g. if you deployed a contract that needs funds
    // for a governance proposal, deal them funds
    function afterDeploySetup(Addresses) external;

    /// After finishing deploy and deploy cleanup, build the proposal
    function build(Addresses) external;

    // Actually run the proposal (e.g. queue actions in the Timelock,
    // or execute a serie of Multisig calls...).
    // See contracts/test/proposals/proposalTypes for helper contracts.
    function run(Addresses, address) external;

    // After a proposal executed, if you mocked some behavior in the
    // afterDeploy step, you might want to tear down the mocks here.
    // For instance, in afterDeploy() you could impersonate the multisig
    // of another protocol to do actions in their protocol (in anticipation
    // of changes that must happen before your proposal execution), and here
    // you could revert these changes, to make sure the integration tests
    // run on a state that is as close to mainnet as possible.
    function teardown(Addresses, address) external;

    // For small post-proposal checks, e.g. read state variables of the
    // contracts you deployed, to make sure your deploy() and afterDeploy()
    // steps have deployed contracts in a correct configuration, or read
    // states that are expected to have change during your run() step.
    // Note that there is a set of tests that run post-proposal in
    // contracts/test/integration/post-proposal-checks, as well as
    // tests that read state before proposals & after, in
    // contracts/test/integration/proposal-checks, so this validate()
    // step should only be used for small checks.
    // If you want to add extensive validation of a new component
    // deployed by your proposal, you might want to add a post-proposal
    // test file instead.
    function validate(Addresses, address) external;

    /// print out proposal steps one by one
    /// print proposal description
    function printProposalActionSteps() external;
}

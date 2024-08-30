// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {String} from "@utils/String.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract PostProposalCheck is Test {
    using String for string;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice  proposals array
    Proposal[] public proposals;

    /// @notice governor address
    MultichainGovernor governor;

    function setUp() public virtual {
        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposals = new Proposal[](3);

        governor = MultichainGovernor(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
        );

        // get the latest moonbeam proposal
        proposals[0] = checkAndRunLatestProposal(
            "bin/get-latest-moonbeam-proposal.sh"
        );

        // get the latest base proposal
        proposals[1] = checkAndRunLatestProposal(
            "bin/get-latest-base-proposal.sh"
        );

        // get the latest multichain proposal
        proposals[2] = checkAndRunLatestProposal(
            "bin/get-latest-multichain-proposal.sh"
        );

        /// only etch out precompile contracts if on the moonbeam chain
        if (
            addresses.isAddressSet("xcUSDT") &&
            addresses.isAddressSet("xcUSDC") &&
            addresses.isAddressSet("xcDOT")
        ) {
            etch(vm, addresses);
        }
    }

    function checkAndRunLatestProposal(
        string memory scriptPath
    ) private returns (Proposal) {
        string[] memory inputs = new string[](1);
        inputs[0] = scriptPath;

        string memory output = string(vm.ffi(inputs));

        Proposal proposal = Proposal(deployCode(output));
        vm.makePersistent(address(proposal));

        vm.selectFork(proposal.primaryForkId());

        address deployer = address(this);

        proposal.deploy(addresses, deployer);
        proposal.afterDeploy(addresses, deployer);
        proposal.preBuildMock(addresses);
        proposal.build(addresses);

        // only runs the proposal if the proposal has not been executed yet
        if (proposal.getProposalId(addresses, address(governor)) == 0) {
            proposal.teardown(addresses, deployer);
            proposal.run(addresses, deployer);
            proposal.validate(addresses, deployer);
        }

        return proposal;
    }
}

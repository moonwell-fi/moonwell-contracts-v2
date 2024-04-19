pragma solidity 0.8.19;

import {IMultichainGovernor, MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Script} from "@forge-std/Script.sol";
import "@forge-std/Test.sol";

contract ValidateActiveProposals is Script, Test {
    /// @notice addresses contract
    Addresses addresses;

    constructor() {
        addresses = new Addresses();
    }

    function run() public {
        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        uint256[] memory proposalIds = governor.liveProposals();

        for (uint256 i = 0; i < proposalIds.length; i++) {
            (address[] memory targets, , ) = governor.getProposalData(
                proposalIds[i]
            );

            for (uint256 j = 0; j < targets.length; j++) {
                require(
                    targets[j].code.length > 0,
                    "Proposal target not a contract"
                );
            }
        }
    }
}

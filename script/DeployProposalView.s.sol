// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {ProposalView} from "@protocol/views/ProposalView.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/*
How to use:
forge script script/DeployProposalView .s.sol:DeployProposalView \
    -vvvv \
    --rpc-url base \
    --etherscan-api-key base --verify --broadcast 
Remove --broadcast if you want to try locally first, without paying any gas.
*/
contract DeployProposalView is Script {
    bytes32 public constant salt = keccak256("PROPOSAL_VIEW");

    function run() public {
        Addresses addresses = new Addresses();

        address relayer = addresses.getAddress("RELAYER");

        vm.startBroadcast();
        ProposalView proposalView = new ProposalView{salt: salt}(relayer);

        vm.stopBroadcast();

        console.log(
            "successfully deployed ProposalView: %s",
            address(proposalView)
        );
    }
}

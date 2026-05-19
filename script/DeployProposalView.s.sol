// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {ProposalView} from "@protocol/views/ProposalView.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";

/*
Standalone deployment for the ProposalView contract. Decoupled from any
governance proposal — runnable today, by anyone, against any chain where
TEMPORAL_GOVERNOR is registered in chains/<id>.json.

How to use (Moonbeam):
forge script script/DeployProposalView.s.sol:DeployProposalView \
    -vvvv \
    --rpc-url moonbeam \
    --verify --verifier-url https://api-moonbeam.moonscan.io/api \
    --etherscan-api-key moonbeam \
    --broadcast --always-use-create-2-factory

How to use (Base):
forge script script/DeployProposalView.s.sol:DeployProposalView \
    -vvvv \
    --rpc-url base --etherscan-api-key base \
    --verify --broadcast --always-use-create-2-factory

How to use (Optimism):
forge script script/DeployProposalView.s.sol:DeployProposalView \
    -vvvv \
    --rpc-url optimism --etherscan-api-key optimism \
    --verify --broadcast --always-use-create-2-factory

How to use (Ethereum):
forge script script/DeployProposalView.s.sol:DeployProposalView \
    -vvvv \
    --rpc-url ethereum --etherscan-api-key ethereum \
    --verify --broadcast --always-use-create-2-factory

Omit --broadcast for a dry run (no gas spent). After a successful broadcast,
register the deployed address in chains/<chainId>.json under PROPOSAL_VIEW.
*/
contract DeployProposalView is Script {
    bytes32 public constant salt = keccak256("PROPOSAL_VIEW");

    function run() public {
        Addresses addresses = new Addresses();

        if (addresses.isAddressSet("PROPOSAL_VIEW", block.chainid)) {
            console.log(
                "PROPOSAL_VIEW already deployed on chain %s at %s - skipping",
                block.chainid,
                addresses.getAddress("PROPOSAL_VIEW")
            );
            return;
        }

        ITemporalGovernor temporalGovernor = ITemporalGovernor(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        vm.startBroadcast();
        ProposalView proposalView = new ProposalView{salt: salt}(
            temporalGovernor
        );
        vm.stopBroadcast();

        console.log(
            "successfully deployed ProposalView on chain %s: %s",
            block.chainid,
            address(proposalView)
        );
        console.log(
            "  referencing TemporalGovernor:",
            address(temporalGovernor)
        );
        console.log(
            "  remember to register this under PROPOSAL_VIEW in chains/<chainId>.json"
        );
    }
}

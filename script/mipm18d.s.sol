pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";

import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";

import {mipm18d} from "@proposals/mips/mip-m18/mip-m18d.sol";

// forge script script/mipm18d.s.sol -vvvv --unlocked --sender 0xfc4DFB17101A12C5CEc5eeDd8E92B5b16557666d
contract mipm18dScript is Script {
    /// @notice addresses contract
    Addresses addresses;
    Proposal[] public proposals;
    mipm18d public proposalD;

    constructor() {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposalD = new mipm18d();
        vm.makePersistent(address(proposalD));

        proposals.push(Proposal(address(proposalD)));
    }

    function run() public {
        vm.selectFork(proposalD.primaryForkId());

        proposalD.build(addresses);

        // simulate
        proposalD.run(addresses, address(proposalD));

        // get actions
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory datas,
            bool[] memory isMoonbeam,

        ) = proposalD.getProposalActionSteps();

        uint256 eta = block.timestamp + 86400;

        Timelock timelock = Timelock(addresses.getAddress("MOONBEAM_TIMELOCK"));

        vm.startPrank(addresses.getAddress("ARTEMIS_GOVERNOR"));

        for (uint256 i = 0; i < targets.length; i++) {
            if (isMoonbeam[i]) {
                timelock.queueTransaction(
                    targets[i],
                    values[i],
                    "",
                    datas[i],
                    eta
                );
            }
        }

        vm.warp(eta);

        for (uint256 i = 0; i < targets.length; i++) {
            if (isMoonbeam[i]) {
                timelock.executeTransaction(
                    targets[i],
                    values[i],
                    "",
                    datas[i],
                    eta
                );
            }
        }
    }
}

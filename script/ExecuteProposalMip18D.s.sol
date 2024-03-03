pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";
import "@forge-std/Test.sol";
import {mipm18d} from "@proposals/mips/mip-m18/mip-m18d.sol";

contract ExecuteProposalMip18D is  mipm18d {
    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    Addresses addresses;

    mipm18d proposalD;

    constructor() {
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();

        build(addresses);
    }

    function run() public override {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas
        ) = getTargetsPayloadsValues(addresses);

        string[] memory signatures = new string[](targets.length);

        string memory sig = "";
        for (uint256 i = 0; i < signatures.length; i++) {
            signatures[i] = sig;
        }
        
        MoonwellArtemisGovernor governor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );

        vm.selectFork(moonbeamForkId);
        vm.startBroadcast(PRIVATE_KEY);
        uint256 proposalId = governor.propose(
            targets,
            values,
            signatures,
            calldatas,
            string(proposalD.PROPOSAL_DESCRIPTION())
        );

        vm.stopBroadcast();

        console.log("proposalId: %s", proposalId);
    }
}

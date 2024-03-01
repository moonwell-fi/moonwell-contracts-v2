pragma solidity 0.8.19;

import {console} from "@forge-std/console.sol";
import {Script} from "@forge-std/Script.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MoonwellArtemisGovernor} from "@protocol/Governance/deprecated/MoonwellArtemisGovernor.sol";
import "@forge-std/Test.sol";
import {mipm18d} from "@proposals/mips/mip-m18/mip-m18d.sol";

contract ExecuteProposalMip18D is Script, Test {
    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    Addresses addresses;

    mipm18d proposalD;

    constructor() {
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();

        proposalD = new mipm18d();
        proposalD.build(addresses);
    }

    function run() public {
        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            bool[] memory isMoonbeam,
            string[] memory descriptions
        ) = proposalD.getProposalActionSteps();

        string[] memory signatures = new string[](isMoonbeam.length);
        address[] memory finalTargets = new address[](isMoonbeam.length);
        bytes[] memory finalCalldatas = new bytes[](isMoonbeam.length);
        uint256[] memory finalValues = new uint256[](isMoonbeam.length);

        string memory sig = "";

        for (uint256 i = 0; i < targets.length; i++) {
            if (isMoonbeam[i] == true) {
                finalTargets[i] = targets[i];
                finalCalldatas[i] = calldatas[i];
                finalValues[i] = values[i];
                signatures[i] = sig;
            }
        }

        MoonwellArtemisGovernor governor = MoonwellArtemisGovernor(
            addresses.getAddress("ARTEMIS_GOVERNOR")
        );

        string memory description = "Transfer ownership to new governor";

        vm.startBroadcast(PRIVATE_KEY);
        uint256 proposalId = governor.propose(
            finalTargets,
            finalValues,
            signatures,
            finalCalldatas,
            description
        );

        vm.stopBroadcast();

        console.log("proposalId: %s", proposalId);
    }
}

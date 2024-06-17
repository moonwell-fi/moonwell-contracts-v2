pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";

import {console} from "@forge-std/console.sol";
import {Test} from "@forge-std/Test.sol";

import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {IProposal} from "@proposals/proposalTypes/IProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";

/*
How to use:
forge test --fork-url $ETH_RPC_URL --match-contract TestProposals -vvv

Or, from another Solidity file (for post-proposal integration testing):
    TestProposals proposals = new TestProposals();
    proposals.setUp();
    proposals.testProposals();
    Addresses addresses = proposals.addresses();
*/

contract TestMultichainProposals is Test, Initializable {
    Addresses public addresses;
    Proposal[] public proposals;

    bool public DEBUG;
    bool public DO_DEPLOY;
    bool public DO_AFTER_DEPLOY;
    bool public DO_PRE_BUILD_MOCK;
    bool public DO_BUILD;
    bool public DO_RUN;
    bool public DO_TEARDOWN;
    bool public DO_VALIDATE;

    function _initialize(address[] memory _proposals) internal initializer {
        for (uint256 i = 0; i < _proposals.length; i++) {
            proposals.push(Proposal(_proposals[i]));
            vm.makePersistent(_proposals[i]);
        }
    }

    function setUp() public virtual {
        DEBUG = vm.envOr("DEBUG", true);
        DO_DEPLOY = vm.envOr("DO_DEPLOY", true);
        DO_AFTER_DEPLOY = vm.envOr("DO_AFTER_DEPLOY", true);
        DO_PRE_BUILD_MOCK = vm.envOr("DO_PRE_BUILD_MOCK", true);
        DO_BUILD = vm.envOr("DO_BUILD", true);
        DO_RUN = vm.envOr("DO_RUN", true);
        DO_TEARDOWN = vm.envOr("DO_TEARDOWN", true);
        DO_VALIDATE = vm.envOr("DO_VALIDATE", true);

        addresses = new Addresses();

        /// make the Addresses contract persistent so it can be accessed from other chains
        vm.makePersistent(address(addresses));
        vm.makePersistent(address(this));
    }

    function printCalldata(
        uint256 index,
        address temporalGovernor,
        address wormholeCore
    ) public {
        CrossChainProposal(address(proposals[index])).printActions(
            temporalGovernor,
            wormholeCore
        );
    }

    function printProposalActionSteps() public {
        for (uint256 i = 0; i < proposals.length; i++) {
            proposals[i].printProposalActionSteps();
        }
    }

    function runProposals(
        bool debug,
        bool deploy,
        bool afterDeploy,
        bool preBuildMock,
        bool build,
        bool run,
        bool teardown,
        bool validate
    ) public {
        if (debug) {
            console.log(
                "TestProposals: running",
                proposals.length,
                "proposals."
            );
        }

        for (uint256 i = 0; i < proposals.length; i++) {
            string memory name = IProposal(address(proposals[i])).name();
            uint256 forkId = MIPProposal(address(proposals[i])).forkIds(0);

            vm.selectFork(forkId);

            // Deploy step
            if (deploy) {
                if (debug) {
                    console.log("Proposal", name, "deploy()");
                }

                addresses.resetRecordingAddresses(); /// reset the recorded addresses for the next proposal

                proposals[i].deploy(addresses, address(proposals[i])); /// mip itself is the deployer
                if (debug) {
                    (
                        string[] memory recordedNames,
                        uint256[] memory chainIds,
                        address[] memory recordedAddresses
                    ) = addresses.getRecordedAddresses();
                    for (uint256 j = 0; j < recordedNames.length; j++) {
                        console.log(
                            "{\n        'addr': '%s', ",
                            recordedAddresses[j]
                        );
                        console.log("        'chainId': %d,", chainIds[j]);
                        console.log(
                            "        'name': '%s'\n}%s",
                            recordedNames[j],
                            j < recordedNames.length - 1 ? "," : ""
                        );
                    }
                }
            }

            // After-deploy step
            if (afterDeploy) {
                if (debug) console.log("Proposal", name, "afterDeploy()");
                proposals[i].afterDeploy(addresses, address(proposals[i]));
            }

            // After-deploy-setup step
            if (preBuildMock) {
                if (debug) console.log("Proposal", name, "preBuildMock()");
                proposals[i].preBuildMock(addresses);
            }

            // Build step
            if (build) {
                if (debug) console.log("Proposal", name, "build()");
                proposals[i].build(addresses);
            }

            // Run step
            if (run) {
                if (debug) console.log("Proposal", name, "run()");
                proposals[i].run(addresses, address(proposals[i]));
            }

            /// snap back to original fork before running other functions just in case run moved to the wrong fork
            vm.selectFork(forkId);

            // Teardown step
            if (teardown) {
                if (debug) console.log("Proposal", name, "teardown()");
                proposals[i].teardown(addresses, address(proposals[i]));
            }

            // Validate step
            if (validate) {
                if (debug) console.log("Proposal", name, "validate()");
                proposals[i].validate(addresses, address(proposals[i]));
            }

            if (debug) console.log("Proposal", name, "done.");
        }
    }

    function runProposals() public {
        runProposals(
            DEBUG,
            DO_DEPLOY,
            DO_AFTER_DEPLOY,
            DO_PRE_BUILD_MOCK,
            DO_BUILD,
            DO_RUN,
            DO_TEARDOWN,
            DO_VALIDATE
        );
    }
}

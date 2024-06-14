// SPDX-License-Identifier: GPL-3.0-or-late
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {String} from "@utils/String.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract PostProposalCheck is Test {
    using String for string;

    /// @notice addresses contract
    Addresses public addresses;

    /// @notice fork ID for moonbeam
    uint256 public moonbeamForkId =
        vm.createFork(vm.envString("MOONBEAM_RPC_URL"));

    /// @notice fork ID for base
    uint256 public baseForkId = vm.createFork(vm.envString("BASE_RPC_URL"));

    /// @notice  proposals array
    Proposal[] public proposals;

    /// @notice governor address
    MultichainGovernor governor;

    function setUp() public virtual {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        proposals = new Proposal[](2);

        vm.selectFork(moonbeamForkId);
        governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")
        );

        // get the latest moonbeam proposal
        proposals[0] = checkAndRunLatestProposal(
            "./get-latest-moonbeam-proposal.sh"
        );

        // get the latest base proposal
        proposals[1] = checkAndRunLatestProposal(
            "./get-latest-base-proposal.sh"
        );

        /// only etch out precompile contracts if on the moonbeam chain
        if (addresses.isAddressSet("xcUSDT")) {
            MockERC20Params mockUSDT = new MockERC20Params(
                "Mock xcUSDT",
                "xcUSDT"
            );
            address mockUSDTAddress = address(mockUSDT);
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(mockUSDTAddress)
            }

            bytes memory runtimeBytecode = new bytes(codeSize);

            assembly {
                extcodecopy(
                    mockUSDTAddress,
                    add(runtimeBytecode, 0x20),
                    0,
                    codeSize
                )
            }

            vm.etch(addresses.getAddress("xcUSDT"), runtimeBytecode);
            MockERC20Params(addresses.getAddress("xcUSDT")).setSymbol("xcUSDT");
        }

        if (addresses.isAddressSet("xcUSDC")) {
            MockERC20Params mockUSDC = new MockERC20Params(
                "USD Coin",
                "xcUSDC"
            );
            address mockUSDCAddress = address(mockUSDC);
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(mockUSDCAddress)
            }

            bytes memory runtimeBytecode = new bytes(codeSize);

            assembly {
                extcodecopy(
                    mockUSDCAddress,
                    add(runtimeBytecode, 0x20),
                    0,
                    codeSize
                )
            }

            vm.etch(addresses.getAddress("xcUSDC"), runtimeBytecode);
            MockERC20Params(addresses.getAddress("xcUSDC")).setSymbol("xcUSDC");
        }

        if (addresses.isAddressSet("xcDOT")) {
            MockERC20Params mockDot = new MockERC20Params(
                "Mock xcDOT",
                "xcDOT"
            );
            address mockDotAddress = address(mockDot);
            uint256 codeSize;
            assembly {
                codeSize := extcodesize(mockDotAddress)
            }

            bytes memory runtimeBytecode = new bytes(codeSize);

            assembly {
                extcodecopy(
                    mockDotAddress,
                    add(runtimeBytecode, 0x20),
                    0,
                    codeSize
                )
            }

            vm.etch(addresses.getAddress("xcDOT"), runtimeBytecode);
            MockERC20Params(addresses.getAddress("xcDOT")).setSymbol("xcDOT");
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

        proposal.setForkIds(baseForkId, moonbeamForkId);

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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {String} from "@utils/String.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";

contract PostProposalCheck is Test {
    using String for string;

    Addresses public addresses;

    function setUp() public virtual {
        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        // get the latest moonbeam proposal
        string[] memory inputs = new string[](1);
        inputs[0] = "./get-latest-moonbeam-proposal.sh";

        string memory output = string(vm.ffi(inputs));

        address deployer = address(this);

        Proposal moonbeamProposal = Proposal(deployCode(output));
        vm.selectFork(moonbeamProposal.primaryForkId());
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");

        moonbeamProposal.deploy(addresses, deployer);
        moonbeamProposal.afterDeploy(addresses, deployer);
        moonbeamProposal.afterDeploySetup(addresses);
        moonbeamProposal.teardown(addresses, deployer);
        moonbeamProposal.build(addresses);

        // only runs the proposal if the proposal has not been executed yet
        if (!moonbeamProposal.checkOnChainCalldata(governor)) {
            moonbeamProposal.run(addresses, deployer);
            moonbeamProposal.validate(addresses, deployer);
        }

        // get the latest base proposal
        inputs[0] = "./get-latest-base-proposal.sh";

        output = string(vm.ffi(inputs));

        Proposal baseProposal = Proposal(deployCode(output));
        vm.selectFork(baseProposal.primaryForkId());

        baseProposal.deploy(addresses, deployer);
        baseProposal.afterDeploy(addresses, deployer);
        baseProposal.afterDeploySetup(addresses);
        baseProposal.teardown(addresses, deployer);
        baseProposal.build(addresses);

        // only runs the proposal if the proposal has not been executed yet
        if (!baseProposal.checkOnChainCalldata(governor)) {
            baseProposal.run(addresses, deployer);
            baseProposal.validate(addresses, deployer);
        }

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
}

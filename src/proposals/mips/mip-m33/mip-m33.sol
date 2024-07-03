//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ForkID} from "@utils/Enums.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m33/mip-m33.sol:mipm33
contract mipm33 is HybridProposal, ParameterValidation {
    string public constant override name = "MIP-M33";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m33/MIP-M33.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ActionType.Moonbeam;
    }

    function deploy(Addresses addresses, address) public override {
        // DO NOT ADD any mock tokens to Addresses object, just use them to etch bytecode

        {
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

            MockERC20Params(addresses.getAddress("xcUSDT")).symbol();
        }

        {
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

            MockERC20Params(addresses.getAddress("xcUSDC")).symbol();
        }

        {
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

            MockERC20Params(addresses.getAddress("xcDOT")).symbol();
        }
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions
        _pushAction(
            addresses.getAddress("MOONWELL_mWBTC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mWBTCwh")
            ),
            "Set interest rate model for mWBTCwh to updated rate model",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-M33: should have no base actions"
        );

        require(
            moonbeamActions.length == 1,
            "MIP-M33: should have moonbeam actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mWBTCwh"),
            addresses.getAddress("MOONWELL_mWBTC"),
            IRParams({
                baseRatePerTimestamp: 0.02e18,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.187e18,
                jumpMultiplierPerTimestamp: 3e18
            })
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m25/mip-m25.sol:mipm25
contract mipm25 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M25";

    uint256 public constant NEW_MXC_USDC_COLLATERAL_FACTOR = 0.15e18;
    uint256 public constant NEW_MGLIMMER_COLLATERAL_FACTOR = 0.57e18;

    uint256 public constant NEW_MXC_USDC_RESERVE_FACTOR = 0.25e18;
    uint256 public constant NEW_MXC_USDT_RESERVE_FACTOR = 0.25e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m25/MIP-M25.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 2;
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        /// DO NOT ADD any mock tokens to Addresses object, just use them to etch bytecode

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
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mxcUSDC"),
                NEW_MXC_USDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mxcUSDC",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MNATIVE"),
                NEW_MGLIMMER_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MNATIVE",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDC_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDC to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDT to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDT to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x32f3A6134590fc2d9440663d35a2F0a6265F04c4
            ),
            "Set interest rate model for mxcUSDC to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x1Cdb984008dcEe9d06c28654ed31cf82680EeA62
            ),
            "Set interest rate model for mxcUSDT to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0xE1Dd796dBEB5A67CE37CbC52dCD164D0535c901E
            ),
            "Set interest rate model for mFRAX to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0xF22c8255eA615b3Da6CA5CF5aeCc8956bfF07Aa8
            ),
            "Set interest rate model for mUSDCwh to updated rate model",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M25: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateCF(
            addresses,
            addresses.getAddress("mxcUSDC"),
            NEW_MXC_USDC_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MNATIVE"),
            NEW_MGLIMMER_COLLATERAL_FACTOR
        );

        _validateRF(
            addresses.getAddress("mxcUSDC"),
            NEW_MXC_USDC_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("mxcUSDT"),
            NEW_MXC_USDT_RESERVE_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mUSDCwh"),
            addresses.getAddress("mUSDCwh"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.0875e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDC"),
            addresses.getAddress("mxcUSDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.0875e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDT"),
            addresses.getAddress("mxcUSDT"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.0875e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mFRAX"),
            addresses.getAddress("mFRAX"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.0563e18,
                jumpMultiplierPerTimestamp: 4.0e18
            })
        );
    }
}

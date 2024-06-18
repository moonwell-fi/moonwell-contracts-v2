//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m25/mip-m25.sol:mipm25
contract mipm25 is HybridProposal, ParameterValidation {
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
    }

    function primaryForkId() public override returns (ProposalType) {
        return ProposalType.Moonbeam;
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

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mxcUSDC"),
                NEW_MXC_USDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mxcUSDC",
            true
        );

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MNATIVE"),
                NEW_MGLIMMER_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MNATIVE",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDC_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDC to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDT to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_USDT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDT to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mxcUSDC")
            ),
            "Set interest rate model for mxcUSDC to updated rate model",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mxcUSDT")
            ),
            "Set interest rate model for mxcUSDT to updated rate model",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mFRAX")
            ),
            "Set interest rate model for mFRAX to updated rate model",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mUSDCwh")
            ),
            "Set interest rate model for mUSDCwh to updated rate model",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
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

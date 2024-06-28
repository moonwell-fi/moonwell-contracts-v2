//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m27/mip-m27.sol:mipm27
contract mipm29 is HybridProposal, ParameterValidation {
    string public constant override name = "MIP-M29";

    uint256 public constant NEW_MGLIMMER_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_MXC_DOT_RESERVE_FACTOR = 0.35e18;
    uint256 public constant NEW_M_ETHWH_RESERVE_FACTOR = 0.35e18;

    uint256 public constant NEW_M_ETHWH_COLLATERAL_FACTOR = 0.48e18;
    uint256 public constant NEW_M_USDCWH_COLLATERAL_FACTOR = 0.58e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m29/MIP-M29.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 15;
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

        _pushHybridAction(
            addresses.getAddress("mGLIMMER"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MGLIMMER_RESERVE_FACTOR
            ),
            "Set reserve factor for mGLIMMER to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mxcDOT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_MXC_DOT_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcDOT to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("mETHwh"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_M_ETHWH_RESERVE_FACTOR
            ),
            "Set reserve factor for mETHwh to updated reserve factor",
            true
        );

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mETHwh"),
                NEW_M_ETHWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mETHwh",
            true
        );

        _pushHybridAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mUSDCwh"),
                NEW_M_USDCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mUSDCwh",
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

        // Adding transferFrom actions
        _pushHybridAction(
            addresses.getAddress("WELL"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451,
                0x7793E08Eb4525309C46C9BA394cE33361A167ba4,
                6778847000000000000000000
            ),
            "Transfer 6778847 WELL from 0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451 to 0x7793E08Eb4525309C46C9BA394cE33361A167ba4",
            true
        );

        _pushHybridAction(
            addresses.getAddress("WELL"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451,
                0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180,
                6923077000000000000000000
            ),
            "Transfer 6923077 WELL from 0x6972f25AB3FC425EaF719721f0EBD1Cdb58eE451 to 0x8E00D5e02E65A19337Cdba98bbA9F84d4186a180",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            baseActions.length == 0,
            "MIP-M29: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateRF(
            addresses.getAddress("mGLIMMER"),
            NEW_MGLIMMER_RESERVE_FACTOR
        );

        _validateRF(addresses.getAddress("mxcDOT"), NEW_MXC_DOT_RESERVE_FACTOR);

        _validateRF(addresses.getAddress("mETHwh"), NEW_M_ETHWH_RESERVE_FACTOR);

        _validateCF(
            addresses,
            addresses.getAddress("mETHwh"),
            NEW_M_ETHWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("mUSDCwh"),
            NEW_M_USDCWH_COLLATERAL_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDC"),
            addresses.getAddress("mxcUSDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDT"),
            addresses.getAddress("mxcUSDT"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.65e18,
                multiplierPerTimestamp: 0.14e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mFRAX"),
            addresses.getAddress("mFRAX"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.08e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );
    }
}

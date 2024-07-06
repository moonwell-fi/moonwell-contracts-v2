//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MockERC20Params} from "@test/mock/MockERC20Params.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {MOONBEAM_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m27/mip-m27.sol:mipm27
contract mipm27 is HybridProposal, ParameterValidation {
    using ChainIds for uint256;
    using ProposalActions for *;

    string public constant override name = "MIP-M27";

    uint256 public constant NEW_MXC_USDC_RESERVE_FACTOR = 0.30e18;
    uint256 public constant NEW_MXC_USDT_RESERVE_FACTOR = 0.30e18;
    uint256 public constant NEW_USDCWH_RESERVE_FACTOR = 0.30e18;

    uint256 public constant NEW_M_USDCWH_COLLATERAL_FACTOR = 0.59e18;
    uint256 public constant NEW_M_WBTCWH_COLLATERAL_FACTOR = 0.32e18;
    uint256 public constant NEW_M_ETHWH_COLLATERAL_FACTOR = 0.49e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m27/MIP-M27.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 13;
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        etch(vm, addresses);
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

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
                "_setReserveFactor(uint256)",
                NEW_MXC_USDC_RESERVE_FACTOR
            ),
            "Set reserve factor for mxcUSDC to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_USDCWH_RESERVE_FACTOR
            ),
            "Set reserve factor for USDCwh to updated reserve factor",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("mUSDCwh"),
                NEW_M_USDCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of mUSDCwh",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mWBTC"),
                NEW_M_WBTCWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mWBTC",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_mETH"),
                NEW_M_ETHWH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of MOONWELL_mETH",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x0568a3aeb8E78262dEFf75ee68fAC20ae35ffA91
            ),
            "Set interest rate model for mxcUSDC to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mxcUSDT"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0xfC7b55cc7C5BD3aE89aC679c7250AB30754C5cC5
            ),
            "Set interest rate model for mxcUSDT to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mFRAX"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x0f36Dda2b47984434051AeCAa5F9587DEA7f95B7
            ),
            "Set interest rate model for mFRAX to updated rate model",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("mUSDCwh"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_mUSDCwh")
            ),
            "Set interest rate model for mUSDCwh to updated rate model",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M27: should have no base actions"
        );

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        _validateRF(
            addresses.getAddress("mxcUSDC"),
            NEW_MXC_USDC_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("mxcUSDT"),
            NEW_MXC_USDT_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("mUSDCwh"),
            NEW_MXC_USDT_RESERVE_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("mUSDCwh"),
            NEW_M_USDCWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mWBTC"),
            NEW_M_WBTCWH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_mETH"),
            NEW_M_ETHWH_COLLATERAL_FACTOR
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mUSDCwh"),
            addresses.getAddress("mUSDCwh"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.11e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDC"),
            addresses.getAddress("mxcUSDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.11e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mxcUSDT"),
            addresses.getAddress("mxcUSDT"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.11e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_mFRAX"),
            addresses.getAddress("mFRAX"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.75e18,
                multiplierPerTimestamp: 0.11e18,
                jumpMultiplierPerTimestamp: 7.4e18
            })
        );
    }
}

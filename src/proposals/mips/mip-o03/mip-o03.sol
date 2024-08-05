//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

contract mipO03 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-O03";

    // Define new reserve and collateral factors for various assets
    uint256 public constant NEW_WETH_RESERVE_FACTOR = 0.1e18;
    uint256 public constant NEW_USDC_RESERVE_FACTOR = 0.05e18;
    uint256 public constant NEW_USDT_RESERVE_FACTOR = 0.05e18;
    uint256 public constant NEW_DAI_RESERVE_FACTOR = 0.05e18;
    uint256 public constant NEW_WBTC_RESERVE_FACTOR = 0.1e18;
    uint256 public constant NEW_wstETH_RESERVE_FACTOR = 0.1e18;
    uint256 public constant NEW_rETH_RESERVE_FACTOR = 0.1e18;
    uint256 public constant NEW_cbETH_RESERVE_FACTOR = 0.1e18;
    uint256 public constant NEW_OP_RESERVE_FACTOR = 0.25e18;

    uint256 public constant NEW_WETH_COLLATERAL_FACTOR = 0.81e18;
    uint256 public constant NEW_USDC_COLLATERAL_FACTOR = 0.83e18;
    uint256 public constant NEW_USDT_COLLATERAL_FACTOR = 0.83e18;
    uint256 public constant NEW_DAI_COLLATERAL_FACTOR = 0.83e18;
    uint256 public constant NEW_WBTC_COLLATERAL_FACTOR = 0.81e18;
    uint256 public constant NEW_wstETH_COLLATERAL_FACTOR = 0.78e18;
    uint256 public constant NEW_rETH_COLLATERAL_FACTOR = 0.78e18;
    uint256 public constant NEW_cbETH_COLLATERAL_FACTOR = 0.78e18;
    uint256 public constant NEW_OP_COLLATERAL_FACTOR = 0.65e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-o03/MIP-O03.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function build(Addresses addresses) public override {
        // Push actions to update Reserve Factors for different assets
        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_WETH_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell WETH to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_USDC_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell USDC to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_USDT"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_USDT_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell USDT to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_DAI_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell DAI to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_WBTC"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_WBTC_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell WBTC to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_wstETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_wstETH_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell wstETH to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_rETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_rETH_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell rETH to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_cbETH_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell cbETH to updated reserve factor",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("MOONWELL_OP"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_OP_RESERVE_FACTOR
            ),
            "Set reserve factor for Moonwell OP to updated reserve factor",
            ActionType.Optimism
        );

        // Push actions to update Collateral Factors for different assets
        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WETH"),
                NEW_WETH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell WETH",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_USDC"),
                NEW_USDC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell USDC",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_USDT"),
                NEW_USDT_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell USDT",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_DAI"),
                NEW_DAI_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell DAI",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WBTC"),
                NEW_WBTC_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell WBTC",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_wstETH"),
                NEW_wstETH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell wstETH",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_rETH"),
                NEW_rETH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell rETH",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_cbETH"),
                NEW_cbETH_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell cbETH",
            ActionType.Optimism
        );

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_OP"),
                NEW_OP_COLLATERAL_FACTOR
            ),
            "Set collateral factor of Moonwell OP",
            ActionType.Optimism
        );
    }

    function validate(Addresses addresses, address) public view override {
        // Validate Collateral Factors
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            NEW_WETH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_USDC"),
            NEW_USDC_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_USDT"),
            NEW_USDT_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_DAI"),
            NEW_DAI_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WBTC"),
            NEW_WBTC_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_wstETH"),
            NEW_wstETH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_rETH"),
            NEW_rETH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_cbETH"),
            NEW_cbETH_COLLATERAL_FACTOR
        );

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_OP"),
            NEW_OP_COLLATERAL_FACTOR
        );

        // Validate Reserve Factors
        _validateRF(
            addresses.getAddress("MOONWELL_WETH"),
            NEW_WETH_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_USDC"),
            NEW_USDC_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_USDT"),
            NEW_USDT_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_DAI"),
            NEW_DAI_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_WBTC"),
            NEW_WBTC_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_wstETH"),
            NEW_wstETH_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_rETH"),
            NEW_rETH_RESERVE_FACTOR
        );

        _validateRF(
            addresses.getAddress("MOONWELL_cbETH"),
            NEW_cbETH_RESERVE_FACTOR
        );

        _validateRF(addresses.getAddress("MOONWELL_OP"), NEW_OP_RESERVE_FACTOR);
    }
}

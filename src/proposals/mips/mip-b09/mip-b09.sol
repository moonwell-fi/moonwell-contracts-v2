//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ForkID} from "@utils/Enums.sol";

contract mipb09 is Proposal, CrossChainProposal, Configs {
    string public constant override name = "MIP-b09";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    uint256 public constant WETH_PREVIOUS_CF = 0.8e18;
    uint256 public constant WETH_NEW_CF = 0.81e18;

    uint256 public constant USDC_PREVIOUS_CF = 0.82e18;
    uint256 public constant USDC_NEW_CF = 0.83e18;

    uint256 public constant cbETH_PREVIOUS_CF = 0.75e18;
    uint256 public constant cbETH_NEW_CF = 0.76e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b09/MIP-B09.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Base;
    }

    function _validateCF(
        Addresses addresses,
        address tokenAddress,
        uint256 collateralFactor
    ) internal view {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");
        Comptroller unitroller = Comptroller(unitrollerAddress);

        (bool listed, uint256 collateralFactorMantissa) = unitroller.markets(
            tokenAddress
        );

        assertTrue(listed);

        assertEq(
            collateralFactorMantissa,
            collateralFactor,
            "collateral factor validation failed"
        );
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        // =========== ETH CF Update ============

        // Add update action
        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WETH"),
                WETH_NEW_CF
            ),
            "Set collateral factor for ETH"
        );

        // =========== USDC CF Update ============

        // Add update action
        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_USDC"),
                USDC_NEW_CF
            ),
            "Set collateral factor for USDC"
        );

        // =========== cbETH CF Update ============

        // Add update action
        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_cbETH"),
                cbETH_NEW_CF
            ),
            "Set collateral factor for USDC"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        // ======== WETH CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            WETH_NEW_CF
        );

        // ======== USDC CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_USDC"),
            USDC_NEW_CF
        );

        // ======== USDC CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_cbETH"),
            cbETH_NEW_CF
        );
    }
}

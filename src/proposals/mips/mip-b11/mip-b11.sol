//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/IRModels/JumpRateModel.sol";
import {TimelockProposal} from "@proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

contract mipb11 is Proposal, CrossChainProposal, Configs {
    string public constant name = "MIP-b11";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    uint256 public constant wstETH_NEW_CF = 0.76e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b11/MIP-B11.md")
        );
        _setProposalDescription(proposalDescription);
    }

    struct IRParams {
        uint256 kink;
        uint256 baseRatePerTimestamp;
        uint256 multiplierPerTimestamp;
        uint256 jumpMultiplierPerTimestamp;
    }

    function _validateJRM(
        address jrmAddress,
        address tokenAddress,
        IRParams memory params
    ) internal {
        JumpRateModel jrm = JumpRateModel(jrmAddress);
        assertEq(
            address(MToken(tokenAddress).interestRateModel()),
            address(jrm),
            "interest rate model not set correctly"
        );

        assertEq(jrm.kink(), params.kink, "kink verification failed");
        assertEq(
            jrm.timestampsPerYear(),
            timestampsPerYear,
            "timestamps per year verifiacation failed"
        );
        assertEq(
            jrm.baseRatePerTimestamp(),
            (params.baseRatePerTimestamp * SCALE) / timestampsPerYear / SCALE,
            "base rate per timestamp validation failed"
        );
        assertEq(
            jrm.multiplierPerTimestamp(),
            (params.multiplierPerTimestamp * SCALE) / timestampsPerYear / SCALE,
            "multiplier per timestamp validation failed"
        );
        assertEq(
            jrm.jumpMultiplierPerTimestamp(),
            (params.jumpMultiplierPerTimestamp * SCALE) /
                timestampsPerYear /
                SCALE,
            "jump multiplier per timestamp validation failed"
        );
    }

    function _validateCF(
        Addresses addresses,
        address tokenAddress,
        uint256 collateralFactor
    ) internal {
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

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_wstETH"),
                wstETH_NEW_CF
            ),
            "Set collateral factor for Moonwell wstETH to updated collateral factor"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDBC")
            ),
            "Set interest rate model for Moonwell USDBC to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_wstETH"),
            wstETH_NEW_CF
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDBC"),
            addresses.getAddress("MOONWELL_USDBC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.7e18,
                multiplierPerTimestamp: 0.057e18,
                jumpMultiplierPerTimestamp: 5.7e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC"),
            addresses.getAddress("MOONWELL_USDC"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.05e18,
                jumpMultiplierPerTimestamp: 8.6e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI"),
            addresses.getAddress("MOONWELL_DAI"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.05e18,
                jumpMultiplierPerTimestamp: 8.6e18
            })
        );
    }
}

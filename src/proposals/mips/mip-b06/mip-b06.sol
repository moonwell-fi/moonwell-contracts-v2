//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/irm/JumpRateModel.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {ForkID} from "@utils/Enums.sol";

contract mipb06 is Proposal, CrossChainProposal, Configs {
    string public constant override name = "MIP-B06";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    uint256 public constant USDC_PREVIOUS_CF = 0.8e18;
    uint256 public constant USDC_NEW_CF = 0.82e18;

    uint256 public constant WETH_PREVIOUS_CF = 0.78e18;
    uint256 public constant WETH_NEW_CF = 0.8e18;

    struct IRParams {
        uint256 kink;
        uint256 baseRatePerTimestamp;
        uint256 multiplierPerTimestamp;
        uint256 jumpMultiplierPerTimestamp;
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b06/MIP-B06.md")
        );
        _setProposalDescription(proposalDescription);

        onchainProposalId = 54;
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Base;
    }

    function _validateJRM(
        address jrmAddress,
        address tokenAddress,
        IRParams memory params
    ) internal view {
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

        // =========== WETH IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x142DCAEC322aAA25141B2597bf348487aDBd596d
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );

        // =========== USDC/DAI/USDbC IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x492dcEF1fc5253413fC5576B9522840a1A774DCe
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x492dcEF1fc5253413fC5576B9522840a1A774DCe
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x492dcEF1fc5253413fC5576B9522840a1A774DCe
            ),
            "Set interest rate model for Moonwell USDbC to updated rate model"
        );

        // =========== cbETH IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_cbETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                0x78Fe5d0427E669ba9F964C3495fF381a805a0487
            ),
            "Set interest rate model for Moonwell cbETH to updated rate model"
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

        // =========== WETH IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                baseRatePerTimestamp: 0.01e18,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.037e18,
                jumpMultiplierPerTimestamp: 4.8e18
            })
        );

        // =========== USDC/DAI/USDbC IR Update ============

        IRParams memory stablecoinIRParams = IRParams({
            baseRatePerTimestamp: 0,
            kink: 0.8e18,
            multiplierPerTimestamp: 0.045e18,
            jumpMultiplierPerTimestamp: 8.6e18
        });

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI"),
            addresses.getAddress("MOONWELL_DAI"),
            stablecoinIRParams
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC"),
            addresses.getAddress("MOONWELL_USDC"),
            stablecoinIRParams
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDBC"),
            addresses.getAddress("MOONWELL_USDBC"),
            stablecoinIRParams
        );

        // =========== cbETH IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_cbETH"),
            addresses.getAddress("MOONWELL_cbETH"),
            IRParams({
                baseRatePerTimestamp: 0,
                kink: 0.45e18,
                multiplierPerTimestamp: 0.07e18,
                jumpMultiplierPerTimestamp: 3.15e18
            })
        );
    }
}

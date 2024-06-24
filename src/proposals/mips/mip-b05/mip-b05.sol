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
import {BASE_FORK_ID} from "@utils/ChainIds.sol";

contract mipb05 is Proposal, CrossChainProposal, Configs {
    string public constant override name = "MIP-b05";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    uint256 public constant ETH_PREVIOUS_CF = 0.75e18;
    uint256 public constant ETH_NEW_CF = 0.78e18;

    uint256 public constant cbETH_PREVIOUS_CF = 0.73e18;
    uint256 public constant cbETH_NEW_CF = 0.75e18;

    uint256 public constant DAI_PREVIOUS_CF = 0.8e18;
    uint256 public constant DAI_NEW_CF = 0.82e18;

    struct IRParams {
        uint256 kink;
        uint256 baseRatePerTimestamp;
        uint256 multiplierPerTimestamp;
        uint256 jumpMultiplierPerTimestamp;
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b05/MIP-B05.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
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
                ETH_NEW_CF
            ),
            "Set collateral factor for ETH"
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
            "Set collateral factor for cbETH"
        );

        // =========== DAI CF Update ============

        // Add update action
        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_DAI"),
                DAI_NEW_CF
            ),
            "Set collateral factor for DAI"
        );

        // =========== WETH IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model"
        );

        // =========== DAI IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model"
        );

        // =========== USDC IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC")
            ),
            "Set interest rate model for Moonwell USDC to updated rate model"
        );

        // =========== USDbC IR Update ============

        // Add update action
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_USDBC"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDBC")
            ),
            "Set interest rate model for Moonwell USDbC to updated rate model"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        // ======== ETH CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            ETH_NEW_CF
        );

        // ======== cbETH CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_cbETH"),
            cbETH_NEW_CF
        );

        // ======== DAI CF Update =========
        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_DAI"),
            DAI_NEW_CF
        );

        // =========== WETH IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                baseRatePerTimestamp: 0.01e18,
                kink: 0.8e18,
                multiplierPerTimestamp: 0.04e18,
                jumpMultiplierPerTimestamp: 4.8e18
            })
        );

        IRParams memory stablecoinIRParams = IRParams({
            baseRatePerTimestamp: 0,
            kink: 0.8e18,
            multiplierPerTimestamp: 0.045e18,
            jumpMultiplierPerTimestamp: 2.5e18
        });

        // =========== DAI IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI"),
            addresses.getAddress("MOONWELL_DAI"),
            stablecoinIRParams
        );

        // =========== USDC IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDC"),
            addresses.getAddress("MOONWELL_USDC"),
            stablecoinIRParams
        );

        // =========== USDbC IR Update ============

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_USDBC"),
            addresses.getAddress("MOONWELL_USDBC"),
            stablecoinIRParams
        );
    }
}

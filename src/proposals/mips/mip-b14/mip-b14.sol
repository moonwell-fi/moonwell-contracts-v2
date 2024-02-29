//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {JumpRateModel} from "@protocol/IRModels/JumpRateModel.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ChainlinkOracle} from "@protocol/Oracles/ChainlinkOracle.sol";
import {TimelockProposal} from "@proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

contract mipb14 is HybridProposal, Configs, ParameterValidation {
    string public constant name = "MIP-b14";

    uint256 public constant BUSD_ORACLE_PRICE = 1e18;

    uint256 public constant wstETH_NEW_RF = 0.3e18;
    uint256 public constant rETH_NEW_RF = 0.3e18;
    uint256 public constant cbETH_NEW_RF = 0.3e18;
    uint256 public constant DAI_NEW_RF = 0.2e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b14/MIP-B14.md")
        );
        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses addresses, address) public override {}

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");
        _run(timelock, moonbeamActions);

        vm.selectFork(baseForkId);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        _run(temporalGovernor, baseActions);

        // switch back to the primary fork so we can run the validations
        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            abi.encodeWithSignature(
                "setUnderlyingPrice(address,uint256)",
                addresses.getAddress("MOONWELL_mBUSD"),
                BUSD_ORACLE_PRICE
            ),
            "Override Chainlink and set BUSD oracle price to $1",
            true
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_DAI"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI")
            ),
            "Set interest rate model for Moonwell DAI to updated rate model",
            false
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH")
            ),
            "Set interest rate model for Moonwell WETH to updated rate model",
            false
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_wstETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                wstETH_NEW_RF
            ),
            "Set reserve factor for Moonwell wstETH to updated reserve factor",
            false
        );

        _pushHybridAction(
            addresses.getAddress("MOONWELL_rETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                rETH_NEW_RF
            ),
            "Set reserve factor for Moonwell rETH to updated reserve factor",
            false
        );
    }

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        assertEq(
            ChainlinkOracle(addresses.getAddress("CHAINLINK_ORACLE"))
                .getUnderlyingPrice(
                    MToken(addresses.getAddress("MOONWELL_mBUSD"))
                ),
            BUSD_ORACLE_PRICE,
            "BUSD oracle price not set correctly"
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_DAI"),
            addresses.getAddress("MOONWELL_DAI"),
            IRParams({
                kink: 0.75e18,
                baseRatePerTimestamp: 0,
                multiplierPerTimestamp: 0.067e18,
                jumpMultiplierPerTimestamp: 9.0e18
            })
        );

        _validateJRM(
            addresses.getAddress("JUMP_RATE_IRM_MOONWELL_WETH"),
            addresses.getAddress("MOONWELL_WETH"),
            IRParams({
                kink: 0.8e18,
                baseRatePerTimestamp: 0,
                multiplierPerTimestamp: 0.032e18,
                jumpMultiplierPerTimestamp: 4.2e18
            })
        );

        _validateRF(
            addresses.getAddress("MOONWELL_wstETH"),
            wstETH_NEW_RF
        );

        _validateRF(
            addresses.getAddress("MOONWELL_rETH"),
            rETH_NEW_RF
        );

        _validateRF(
            addresses.getAddress("MOONWELL_DAI"),
            DAI_NEW_RF
        );

        _validateRF(
            addresses.getAddress("MOONWELL_cbETH"),
            cbETH_NEW_RF
        );
    }
}

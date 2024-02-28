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
    uint256 public constant rETH_NEW_CF = 0.78e18;
    uint256 public constant cbETH_NEW_CF = 0.78e18;

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

    function run(Addresses addresses, address) public virtual override {
        _run(addresses.getAddress("MOONBEAM_TIMELOCK"), moonbeamActions);
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
    }
}

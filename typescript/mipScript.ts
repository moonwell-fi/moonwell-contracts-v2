import {
  CollateralFactorUpdate,
  InterestRateModelUpdate,
  Proposal,
} from "./generator";

import prettier from "prettier";
import solidityPlugin from "prettier-plugin-solidity";

export async function generateMipScript(
  name: string,
  proposal: Proposal
): Promise<string> {
  // Remove hyphens from name
  const contractName = name.replace("-", "");

  const collateralUpdates = proposal.updates.filter(
    (update) => "collateralFactor" in update
  ) as CollateralFactorUpdate[];

  const interestRateModelUpdates = proposal.updates.filter(
    (update) => "interestRateModel" in update
  ) as InterestRateModelUpdate[];

  const output = `//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {JumpRateModel} from "@protocol/IRModels/JumpRateModel.sol";
import {TimelockProposal} from "@proposals/proposalTypes/TimelockProposal.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {ParameterSetting} from "@proposals/utils/ParameterSetting.sol";
import {Comptroller} from "@protocol/Comptroller.sol";

contract ${contractName} is Proposal, CrossChainProposal, Configs, ParameterValidation, ParameterSetting {
    string public constant name = "${name}";

    ${collateralUpdates
      .map(
        (update) =>
          `uint256 public constant ${update.asset}_NEW_CF = ${update.collateralFactor}e18;`
      )
      .join("\n")}

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/${name}/${name}.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        ${collateralUpdates
          .map(
            (update) =>
              `_setCollateralFactor(
                  addresses,
                  "MOONWELL_${update.asset}",
                  ${update.asset}_NEW_CF
              );`
          )
          .join("\n")}

        ${interestRateModelUpdates
          .map(
            (update) =>
              `_setInterestRateModel(
                  addresses,
                  "MOONWELL_${update.asset}",
                  "JUMP_RATE_IRM_MOONWELL_${update.asset}"
              );`
          )
          .join("\n")}
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
        ${collateralUpdates
          .map(
            (update) =>
              `_validateCF(
                  addresses,
                  addresses.getAddress("MOONWELL_${update.asset}"),
                  ${update.asset}_NEW_CF
              );`
          )
          .join("\n")}

        ${interestRateModelUpdates
          .map(
            (update) =>
              `_validateJRM(
                  addresses.getAddress("JUMP_RATE_IRM_MOONWELL_${update.asset}"),
                  addresses.getAddress("MOONWELL_${update.asset}"),
                  IRParams({
                      baseRatePerTimestamp: ${update.interestRateModel.params.baseRatePerTimestamp}e18,
                      kink: ${update.interestRateModel.params.kink}e18,
                      multiplierPerTimestamp: ${update.interestRateModel.params.multiplierPerTimestamp}e18,
                      jumpMultiplierPerTimestamp: ${update.interestRateModel.params.jumpMultiplierPerTimestamp}e18
                  })
              );`
          )
          .join("\n")}
    }
}`;

  const formattedOutput = await prettier.format(output, {
    parser: "solidity-parse",
    plugins: [solidityPlugin],
  });

  return formattedOutput;
}

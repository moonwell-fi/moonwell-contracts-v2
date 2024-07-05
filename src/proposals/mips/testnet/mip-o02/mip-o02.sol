//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {EnumerableSet} from "@openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MIPProposal} from "@proposals/MIPProposal.s.sol";
import {EIP20Interface} from "@protocol/EIP20Interface.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {JumpRateModel, InterestRateModel} from "@protocol/irm/JumpRateModel.sol";
import {Comptroller, ComptrollerInterface} from "@protocol/Comptroller.sol";

/// @notice This lists all new markets provided in `mainnetMTokens.json`
/// This is a template of a MIP proposal that can be used to add new mTokens
/// @dev be sure to include all necessary underlying and price feed addresses
/// in the Addresses.sol contract for the network the MTokens are being deployed on.
contract mipo02 is Proposal, CrossChainProposal, Configs, ParameterValidation {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice the name of the proposal
    /// Read more here: https://forum.moonwell.fi/t/add-aero-market-on-base/873
    string public constant override name = "MIP-o02";

    uint256 public constant COLLATERAL_FACTOR = 0.8e18;

    /// @notice list of all mTokens that were added to the market with this proposal
    EnumerableSet.AddressSet private mTokens;

    constructor() {
        string
            memory descriptionPath = "./src/proposals/mips/mip-b17/MIP-B17.md";
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(descriptionPath)
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function preBuildMock(Addresses) public override {}

    function teardown(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress("MOONWELL_WETH"),
                COLLATERAL_FACTOR
            ),
            "Set Collateral Factor for MToken market in comptroller"
        );

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_supportMarket(address)",
                addresses.getAddress("MOONWELL_USDC")
            ),
            "Support MToken market in comptroller"
        );
    }

    function run(
        Addresses addresses,
        address
    ) public override(CrossChainProposal, MIPProposal) {
        printCalldata(addresses);
        _simulateCrossChainActions(
            addresses,
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
    }

    function validate(Addresses addresses, address) public override {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _validateCF(
            addresses,
            addresses.getAddress("MOONWELL_WETH"),
            COLLATERAL_FACTOR
        );
    }
}

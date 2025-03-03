//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IMetaMorphoBase} from "@protocol/morpho/IMetaMorpho.sol";
import {OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {FeeSplitter as Splitter} from "@protocol/morpho/FeeSplitter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// proposals/mips/mip-o13/mip-o13.sol:mipo13
contract mipo13 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-O13";

    uint256 public constant PERFORMANCE_FEE = 0.15e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-O13/MIP-O13.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the Moonwell USDC Metamorpho Vault"
        );
    }

    function teardown(Addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        /// --------------------- METAMORPHO VAULTS ---------------------

        /// actual owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("USDC_METAMORPHO_VAULT")
            ).owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "USDC Metamorpho Vault ownership incorrect"
        );

        /// pending owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("USDC_METAMORPHO_VAULT")
            ).pendingOwner(),
            address(0),
            "USDC Metamorpho Vault pending owner incorrect"
        );

        /// --------------------- SPLITTERS ---------------------

        Splitter usdcSplitter = Splitter(
            addresses.getAddress("USDC_METAMORPHO_FEE_SPLITTER")
        );

        assertEq(
            usdcSplitter.mToken(),
            addresses.getAddress("MOONWELL_USDC"),
            "USDC Metamorpho Fee Splitter fee recipient incorrect"
        );
        assertEq(
            usdcSplitter.metaMorphoVault(),
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            "USDC Metamorpho Fee Splitter Vault incorrect"
        );
        assertEq(
            usdcSplitter.splitA(),
            5_000,
            "USDC Metamorpho Fee Split incorrect"
        );
        assertEq(
            usdcSplitter.splitB(),
            5_000,
            "USDC Metamorpho Fee Split incorrect"
        );

        /// ---------------- PAUSE GUARDIAN / TIMELOCK DURATION ----------------

        assertEq(
            IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                .guardian(),
            addresses.getAddress("PAUSE_GUARDIAN"),
            "USDC Metamorpho Vault pause guardian incorrect"
        );
        assertEq(
            IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                .timelock(),
            4 days,
            "USDC Metamorpho Vault timelock incorrect"
        );

        /// --------------------- PERFORMANCE FEES ---------------------

        assertEq(
            uint256(
                IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                    .fee()
            ),
            PERFORMANCE_FEE,
            "USDC Metamorpho Vault performance fee incorrect"
        );
    }
}

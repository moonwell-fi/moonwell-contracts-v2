//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IMetaMorphoBase} from "@protocol/morpho/IMetaMorpho.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {FeeSplitter as Splitter} from "@protocol/morpho/FeeSplitter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// DO_PRE_BUILD_MOCK=true DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b30/mip-b30.sol:mipb30
contract mipb30 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B30";

    uint256 public constant PERFORMANCE_FEE = 0.15e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b30/MIP-B30.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setFee(uint256)", PERFORMANCE_FEE),
            "Set the performance fee for the Moonwell USDC Metamorpho Vault"
        );

        _pushAction(
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            abi.encodeWithSignature("setFee(uint256)", PERFORMANCE_FEE),
            "Set the performance fee for the Moonwell WETH Metamorpho Vault"
        );

        _pushAction(
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the Moonwell EURC Metamorpho Vault"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        /// --------------------- METAMORPHO VAULTS ---------------------

        /// actual owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("EURC_METAMORPHO_VAULT")
            ).owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "EURC Metamorpho Vault ownership incorrect"
        );

        /// pending owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("EURC_METAMORPHO_VAULT")
            ).pendingOwner(),
            address(0),
            "EURC Metamorpho Vault pending owner incorrect"
        );

        /// --------------------- SPLITTERS ---------------------

        /// TODO change this to EURC_METAMORPHO_FEE_SPLITTER once deployed
        Splitter eurcSplitter = Splitter(
            addresses.getAddress("USDC_METAMORPHO_FEE_SPLITTER")
        );

        assertEq(
            eurcSplitter.mToken(),
            addresses.getAddress("MOONWELL_EURC"),
            "EURC Metamorpho Fee Splitter fee recipient incorrect"
        );
        assertEq(
            eurcSplitter.metaMorphoVault(),
            addresses.getAddress("EURC_METAMORPHO_VAULT"),
            "EURC Metamorpho Fee Splitter Vault incorrect"
        );
        assertEq(
            eurcSplitter.splitA(),
            5_000,
            "EURC Metamorpho Fee Split incorrect"
        );
        assertEq(
            eurcSplitter.splitB(),
            5_000,
            "EURC Metamorpho Fee Split incorrect"
        );

        /// ---------------- PAUSE GUARDIAN / TIMELOCK DURATION ----------------

        assertEq(
            IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                .guardian(),
            addresses.getAddress("PAUSE_GUARDIAN"),
            "USDC Metamorpho Vault pause guardian incorrect"
        );
        assertEq(
            IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                .timelock(),
            4 days,
            "USDC Metamorpho Vault timelock incorrect"
        );

        /// --------------------- PERFORMANCE FEES ---------------------

        assertEq(
            uint256(
                IMetaMorphoBase(addresses.getAddress("EURC_METAMORPHO_VAULT"))
                    .fee()
            ),
            PERFORMANCE_FEE,
            "USDC Metamorpho Vault performance fee incorrect"
        );
        assertEq(
            uint256(
                IMetaMorphoBase(addresses.getAddress("USDC_METAMORPHO_VAULT"))
                    .fee()
            ),
            PERFORMANCE_FEE,
            "USDC Metamorpho Vault performance fee incorrect"
        );
        assertEq(
            uint256(
                IMetaMorphoBase(addresses.getAddress("WETH_METAMORPHO_VAULT"))
                    .fee()
            ),
            PERFORMANCE_FEE,
            "WETH Metamorpho Vault performance fee incorrect"
        );
    }
}

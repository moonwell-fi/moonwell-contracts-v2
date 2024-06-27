//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {FeeSplitter as Splitter} from "@protocol/morpho/FeeSplitter.sol";
import {ForkID} from "@utils/Enums.sol";

/// DO_PRE_BUILD_MOCK=true DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b21/mip-b21.sol:mipb21
contract mipb21 is HybridProposal, Configs, ParameterValidation {
    string public constant override name = "MIP-B21";

    uint256 public constant WELL_AMOUNT = 50_000_000 * 1e18;

    /// @notice metamorpho storage slot offset for pending owner
    bytes32 public constant PENDING_OWNER_SLOT = bytes32(uint256(9));

    uint256 public startingWellAllowance;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b21/MIP-B21.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (ForkID) {
        return ForkID.Base;
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        startingWellAllowance = ERC20Upgradeable(
            addresses.getAddress("xWELL_PROXY")
        ).allowance(
                addresses.getAddress("FOUNDATION_MULTISIG"),
                temporalGovernor
            );
    }

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("USDC_METAMORPHO_VAULT"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the Moonwell USDC Metamorpho Vault"
        );
        _pushAction(
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept ownership of the Moonwell WETH Metamorpho Vault"
        );
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("FOUNDATION_MULTISIG"),
                addresses.getAddress("MOONWELL_METAMORPHO_URD"),
                WELL_AMOUNT
            ),
            "Transfer 50m WELL from the Foundation Base Multisig to the Moonwell Metamorpho URD"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
        /// --------------------- WELL ---------------------
        ERC20Upgradeable well = ERC20Upgradeable(
            addresses.getAddress("xWELL_PROXY")
        );

        assertEq(
            well.balanceOf(addresses.getAddress("MOONWELL_METAMORPHO_URD")),
            WELL_AMOUNT,
            "well amount incorrect"
        );
        assertEq(
            startingWellAllowance -
                well.allowance(
                    addresses.getAddress("FOUNDATION_MULTISIG"),
                    addresses.getAddress("TEMPORAL_GOVERNOR")
                ),
            WELL_AMOUNT,
            "well allowance decrease incorrect"
        );

        /// --------------------- METAMORPHO VAULTS ---------------------

        /// actual owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("USDC_METAMORPHO_VAULT")
            ).owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "USDC Metamorpho Vault ownership incorrect"
        );

        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WETH_METAMORPHO_VAULT")
            ).owner(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "WETH Metamorpho Vault ownership incorrect"
        );

        /// pending owner
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("USDC_METAMORPHO_VAULT")
            ).pendingOwner(),
            address(0),
            "USDC Metamorpho Vault pending owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WETH_METAMORPHO_VAULT")
            ).pendingOwner(),
            address(0),
            "WETH Metamorpho Vault pending owner incorrect"
        );

        /// --------------------- SPLITTERS ---------------------

        Splitter wethSplitter = Splitter(
            addresses.getAddress("WETH_METAMORPHO_FEE_SPLITTER")
        );

        assertEq(
            wethSplitter.mToken(),
            addresses.getAddress("MOONWELL_WETH"),
            "WETH Metamorpho Fee Splitter fee recipient incorrect"
        );
        assertEq(
            wethSplitter.metaMorphoVault(),
            addresses.getAddress("WETH_METAMORPHO_VAULT"),
            "WETH Metamorpho Fee Splitter Vault incorrect"
        );
        assertEq(
            wethSplitter.splitA(),
            5_000,
            "WETH Metamorpho Fee Split incorrect"
        );
        assertEq(
            wethSplitter.splitB(),
            5_000,
            "WETH Metamorpho Fee Split incorrect"
        );

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
            "USDC Metamorpho Fee Split a incorrect"
        );
        assertEq(
            usdcSplitter.splitB(),
            5_000,
            "USDC Metamorpho Fee Split b incorrect"
        );
    }
}

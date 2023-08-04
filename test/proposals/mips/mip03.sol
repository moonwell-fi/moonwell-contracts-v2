//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MToken} from "@protocol/core/MToken.sol";
import {MErc20} from "@protocol/core/MErc20.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {Comptroller} from "@protocol/core/Comptroller.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";

/// @notice This changes the collateral and reserve factors of the mTokens on the mainnet
/// This is an example of a MIP proposal that can be used to change the parameters of the mTokens.
/// This proposal sets the collateral factor of USDC to 80% and the reserve factor to 15%.
/// @dev be sure to include all necessary underlying and price feed addresses in the Addresses.sol contract for the network
/// the MTokens are being changed on.
contract mip03 is Proposal, CrossChainProposal, ChainIds, Configs {
    /// @notice the name of the proposal
    string public constant name = "MIP03";

    /// @notice collateral factor is 80%
    uint256 public constant newCollateralFactor = 0.8e18;

    /// @notice reserve factor is 15%
    uint256 public constant newReserveFactor = 0.15e18;

    constructor() {
        _setNonce(3);
    }

    /// @notice no contracts are deployed in this proposal
    function deploy(Addresses, address) public {}

    function afterDeploy(Addresses, address) public {}

    function afterDeploySetup(Addresses addresses) public {}

    function build(Addresses addresses) public {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");
        address cTokenAddress = addresses.getAddress("MOONWELL_USDC");

        /// call to the unitroller and set the collateral factor for the market
        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                cTokenAddress,
                newCollateralFactor
            ),
            "Set collateral factor for the market"
        );

        /// call to the cToken and set the reserve factor for the market
        _pushCrossChainAction(
            cTokenAddress,
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                newReserveFactor
            ),
            "Set collateral factor for the market"
        );
    }

    function run(Addresses addresses, address) public {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure {}

    function validate(Addresses addresses, address) public {
        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        address cTokenAddress = addresses.getAddress("MOONWELL_USDC");

        (, uint256 collateralFactorMantissa) = comptroller.markets(
            cTokenAddress
        );
        assertEq(collateralFactorMantissa, newCollateralFactor);

        assertEq(
            MToken(cTokenAddress).reserveFactorMantissa(),
            newReserveFactor
        );
    }
}

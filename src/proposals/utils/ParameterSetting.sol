//SPDX-License-Identifier: GPL-3.0-or-later
import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {CrossChainProposal} from "@proposals/proposalTypes/CrossChainProposal.sol";

abstract contract ParameterSetting is CrossChainProposal {
    function _setCollateralFactor(Addresses addresses, string memory asset, uint256 factor) internal {
        address unitrollerAddress = addresses.getAddress("UNITROLLER");

        _pushCrossChainAction(
            unitrollerAddress,
            abi.encodeWithSignature(
                "_setCollateralFactor(address,uint256)",
                addresses.getAddress(asset),
                factor
            ),
            string.concat("Set collateral factor for ", asset)
        );
    }

    function _setInterestRateModel(Addresses addresses, string memory asset, string memory rateModel) internal {
        _pushCrossChainAction(
            addresses.getAddress(asset),
            abi.encodeWithSignature(
                "_setInterestRateModel(address)",
                addresses.getAddress(rateModel)
            ),
            string.concat("Set interest rate model for ", asset, " to ", rateModel)
        );
    }
}

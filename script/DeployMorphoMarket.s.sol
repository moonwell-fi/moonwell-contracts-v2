// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Addresses} from "@proposals/Addresses.sol";

import {Script} from "@forge-std/Script.sol";

import {ERC20} from "@openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

import {String} from "../src/utils/String.sol";

interface IMorphoBlue {
    struct MarketParams {
        address loanToken;
        address collateralToken;
        address oracle;
        address irm;
        uint256 lltv;
    }

    /// @notice Creates the market `marketParams`.
    /// @dev Here is the list of assumptions on the market's dependencies (tokens, IRM and oracle) that guarantees
    /// Morpho behaves as expected:
    /// - The token should be ERC-20 compliant, except that it can omit return values on `transfer` and `transferFrom`.
    /// - The token balance of Morpho should only decrease on `transfer` and `transferFrom`. In particular, tokens with
    /// burn functions are not supported.
    /// - The token should not re-enter Morpho on `transfer` nor `transferFrom`.
    /// - The token balance of the sender (resp. receiver) should decrease (resp. increase) by exactly the given amount
    /// on `transfer` and `transferFrom`. In particular, tokens with fees on transfer are not supported.
    /// - The IRM should not re-enter Morpho.
    /// - The oracle should return a price with the correct scaling.
    /// @dev Here is a list of properties on the market's dependencies that could break Morpho's liveness properties
    /// (funds could get stuck):
    /// - The token can revert on `transfer` and `transferFrom` for a reason other than an approval or balance issue.
    /// - A very high amount of assets (~1e35) supplied or borrowed can make the computation of `toSharesUp` and
    /// `toSharesDown` overflow.
    /// - The IRM can revert on `borrowRate`.
    /// - A very high borrow rate returned by the IRM can make the computation of `interest` in `_accrueInterest`
    /// overflow.
    /// - The oracle can revert on `price`. Note that this can be used to prevent `borrow`, `withdrawCollateral` and
    /// `liquidate` from being used under certain market conditions.
    /// - A very high price returned by the oracle can make the computation of `maxBorrow` in `_isHealthy` overflow, or
    /// the computation of `assetsRepaid` in `liquidate` overflow.
    /// @dev The borrow share price of a market with less than 1e4 assets borrowed can be decreased by manipulations, to
    /// the point where `totalBorrowShares` is very large and borrowing overflows.
    function createMarket(MarketParams memory params) external;
}

// forge script script/DeployMorphoMarket.s.sol --rpc-url baseSepolia --broadcast
// --verify --sender ${SENDER_WALLET} --account ${WALLET}
contract DeployMorphoMarket is Script {
    using String for string;

    function run() public {
        Addresses addresses = new Addresses();

        string memory loanToken = vm.prompt("Enter the loan token name");
        string memory collateralToken = vm.prompt(
            "Enter the collateral token name"
        );
        string memory oracle = vm.prompt("Enter the oracle token name");
        uint256 lltv = vm.prompt("Enter the lltv ").toUint256();

        //the LLTV is defined with 18 decimals. 1e18 represents an LLTV of 100% (which is not enabled) and 945000000000000000 thus represents 94.5%.
        // Enabled LLTVs: 0%; 38.5%; 62.5%; 77.0%; 86.0%; 91.5%; 94.5%; 96.5%; 98%.

        uint256[] memory enabledLLTVs = new uint256[](9);
        enabledLLTVs[0] = 0.0 * 1e18;
        enabledLLTVs[1] = 0.385 * 1e18;
        enabledLLTVs[2] = 0.625 * 1e18;
        enabledLLTVs[3] = 0.77 * 1e18;
        enabledLLTVs[4] = 0.86 * 1e18;
        enabledLLTVs[5] = 0.915 * 1e18;
        enabledLLTVs[6] = 0.945 * 1e18;
        enabledLLTVs[7] = 0.965 * 1e18;
        enabledLLTVs[8] = 0.98 * 1e18;

        for (uint256 i = 0; i < enabledLLTVs.length; i++) {
            if (lltv == enabledLLTVs[i]) {
                break;
            }
            if (i == enabledLLTVs.length - 1) {
                revert("Invalid LLTV");
            }
        }

        address morpho = addresses.getAddress("MORPHO_BLUE");

        address irm = addresses.getAddress("MORPHO_ADAPTIVE_CURVE_IRM");

        address loanTokenAddress = addresses.getAddress(loanToken);
        address collateralTokenAddress = addresses.getAddress(collateralToken);
        address oracleAddress = addresses.getAddress(oracle);

        IMorphoBlue.MarketParams memory params = IMorphoBlue.MarketParams(
            loanTokenAddress,
            collateralTokenAddress,
            oracleAddress,
            irm,
            lltv.toUint256()
        );

        vm.startBroadcast();

        IMorphoBlue(morpho).createMarket(params);

        vm.stopBroadcast();
    }
}

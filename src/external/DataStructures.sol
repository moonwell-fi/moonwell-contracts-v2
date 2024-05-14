// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Test} from "@forge-std/Test.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";

import {Signers} from "./Signers.sol";

/// Forked-Base fixture shared by every marketplace test. No admin whitelisting
/// happens here — those setters revert `NotImplemented` in PR1 and land in
/// PR2.
abstract contract Fixture is Test, Signers {
    Addresses internal addresses;

    CreditMarketplaceFactory internal factory;
    CreditLoan internal loanImpl;

    address internal temporalGovernor;
    address internal unitroller;
    address internal pauseGuardian;
    address internal usdc;
    address internal cbbtc;
    address internal mUsdc;
    address internal mCbBtc;
    address internal chainlinkBtcUsd;

    address internal feeRecipient;

    address internal backendSignerEOA;
    uint256 internal backendSignerKey;
    address internal lender;
    uint256 internal lenderKey;
    address internal borrower;
    uint256 internal borrowerKey;

    function setUp() public virtual {
        vm.createSelectFork("base");

        addresses = new Addresses();

        temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        unitroller = addresses.getAddress("UNITROLLER");
        pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");
        usdc = addresses.getAddress("USDC");
        cbbtc = addresses.getAddress("cbBTC");
        mUsdc = addresses.getAddress("MOONWELL_USDC");
        mCbBtc = addresses.getAddress("MOONWELL_cbBTC");
        chainlinkBtcUsd = addresses.getAddress("CHAINLINK_BTC_USD");

        feeRecipient = makeAddr("feeRecipient");

        (backendSignerEOA, backendSignerKey) = makeAddrAndKey("backend");
        (lender, lenderKey) = makeAddrAndKey("lender");
        (borrower, borrowerKey) = makeAddrAndKey("borrower");

        loanImpl = new CreditLoan();

        factory = new CreditMarketplaceFactory(
            temporalGovernor,
            unitroller,
            address(loanImpl),
            backendSignerEOA,
            feeRecipient,
            pauseGuardian
        );
    }
}

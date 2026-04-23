// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {CreditLoan} from "@protocol/marketplace/CreditLoan.sol";
import {CreditMarketplaceFactory} from "@protocol/marketplace/CreditMarketplaceFactory.sol";
import {InitParams} from "@protocol/marketplace/CreditTypes.sol";

import {Fixture} from "./Fixture.t.sol";

contract AdminSettersTest is Fixture {
    event BackendSignerUpdated(
        address indexed previousSigner,
        address indexed newSigner
    );
    event CreditLoanImplementationUpdated(
        address indexed previous,
        address indexed updated
    );
    event MTokenWhitelisted(address indexed mToken, bool allowed);
    event CollateralWhitelisted(address indexed token, address indexed feed);
    event CollateralRemoved(address indexed token);
    event PrincipalTokenWhitelisted(
        address indexed token,
        address indexed feed
    );
    event PrincipalTokenRemoved(address indexed token);
    event StalenessWindowUpdated(uint32 seconds_);
    event MinOriginationLtvBufferBpsUpdated(uint16 previous, uint16 updated);
    event DefaultParamsUpdated(
        uint32 gracePeriod,
        uint16 overSeizureBps,
        uint16 consecutiveMissesForDefault,
        uint16 marketplaceFeeBps
    );
    event FeeRecipientUpdated(
        address indexed previous,
        address indexed updated
    );
    event PauseGuardianUpdated(
        address indexed previousGuardian,
        address indexed newGuardian
    );

    string constant NOT_OWNER = "Ownable: caller is not the owner";

    // ─── setBackendSigner ───────────────────────────────────────────
    function test_setBackendSigner_updates() public {
        address newSigner = makeAddr("newBackend");
        vm.expectEmit(true, true, true, true, address(factory));
        emit BackendSignerUpdated(backendSignerEOA, newSigner);
        vm.prank(temporalGovernor);
        factory.setBackendSigner(newSigner);
        assertEq(factory.backendSigner(), newSigner);
    }

    function test_setBackendSigner_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setBackendSigner(makeAddr("x"));
    }

    function test_setBackendSigner_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.setBackendSigner(address(0));
    }

    // ─── setCreditLoanImplementation ───────────────────────────────
    function test_setCreditLoanImplementation_locksAndStores() public {
        CreditLoan fresh = new CreditLoan();
        vm.expectEmit(true, true, true, true, address(factory));
        emit CreditLoanImplementationUpdated(address(loanImpl), address(fresh));
        vm.prank(temporalGovernor);
        factory.setCreditLoanImplementation(address(fresh));

        assertEq(factory.creditLoanImplementation(), address(fresh));

        // Now locked; a direct initialize on it reverts.
        InitParams memory p;
        vm.expectRevert(CreditLoan.AlreadyInitialized.selector);
        fresh.initialize(p);
    }

    function test_setCreditLoanImplementation_nonOwnerReverts() public {
        CreditLoan fresh = new CreditLoan();
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setCreditLoanImplementation(address(fresh));
    }

    function test_setCreditLoanImplementation_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.setCreditLoanImplementation(address(0));
    }

    function test_setCreditLoanImplementation_nonContractReverts() public {
        /// Use a hardcoded address that's empty on Base mainnet. Avoids
        /// EIP-7702 delegation collisions seen with `makeAddr`, which
        /// deterministically maps labels to key-derived addresses that may
        /// already be delegated-EOAs with nonzero code.
        address eoa = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        assertEq(eoa.code.length, 0, "fixture precondition");

        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidImplementation.selector
        );
        factory.setCreditLoanImplementation(eoa);
    }

    function test_setCreditLoanImplementation_alreadyLockedReverts() public {
        CreditLoan fresh = new CreditLoan();
        InitParams memory sentinel;
        fresh.initialize(sentinel);

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditLoan.AlreadyInitialized.selector);
        factory.setCreditLoanImplementation(address(fresh));
    }

    // ─── whitelistMToken ───────────────────────────────────────────
    function test_whitelistMToken_enables() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit MTokenWhitelisted(mUsdc, true);
        vm.prank(temporalGovernor);
        factory.whitelistMToken(mUsdc, true);
        assertTrue(factory.isMTokenWhitelisted(mUsdc));
    }

    function test_whitelistMToken_disables() public {
        vm.prank(temporalGovernor);
        factory.whitelistMToken(mUsdc, true);

        vm.expectEmit(true, true, true, true, address(factory));
        emit MTokenWhitelisted(mUsdc, false);
        vm.prank(temporalGovernor);
        factory.whitelistMToken(mUsdc, false);
        assertFalse(factory.isMTokenWhitelisted(mUsdc));
    }

    function test_whitelistMToken_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.whitelistMToken(mUsdc, true);
    }

    function test_whitelistMToken_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.whitelistMToken(address(0), true);
    }

    // ─── whitelistCollateralToken ──────────────────────────────────
    function test_whitelistCollateralToken_liveFeed() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit CollateralWhitelisted(cbbtc, chainlinkBtcUsd);
        vm.prank(temporalGovernor);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );
        assertTrue(factory.isCollateralWhitelisted(cbbtc));
        assertEq(address(factory.collateralFeeds(cbbtc)), chainlinkBtcUsd);
    }

    function test_whitelistCollateralToken_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );
    }

    function test_whitelistCollateralToken_zeroTokenReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.whitelistCollateralToken(
            address(0),
            AggregatorV3Interface(chainlinkBtcUsd)
        );
    }

    function test_whitelistCollateralToken_zeroFeedReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(address(0))
        );
    }

    function test_whitelistCollateralToken_negativeAnswerReverts() public {
        address fakeFeed = makeAddr("fakeFeed");
        _mockDecimals(fakeFeed, 8);
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(0),
                int256(-1),
                uint256(0),
                block.timestamp,
                uint80(0)
            )
        );

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidOraclePrice.selector);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(fakeFeed)
        );
    }

    function test_whitelistCollateralToken_feedDecimalsTooHighReverts() public {
        address fakeFeed = makeAddr("fakeFeed");
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(uint8(19))
        );

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidFeedDecimals.selector);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(fakeFeed)
        );
    }

    function test_whitelistCollateralToken_staleFeedReverts() public {
        address fakeFeed = makeAddr("fakeFeed");
        _mockDecimals(fakeFeed, 8);
        uint256 old = block.timestamp - 2 days;
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(uint80(0), int256(1e8), uint256(0), old, uint80(0))
        );

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.StaleOraclePrice.selector);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(fakeFeed)
        );
    }

    // ─── removeCollateralToken ─────────────────────────────────────
    function test_removeCollateralToken_clears() public {
        vm.prank(temporalGovernor);
        factory.whitelistCollateralToken(
            cbbtc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit CollateralRemoved(cbbtc);
        vm.prank(temporalGovernor);
        factory.removeCollateralToken(cbbtc);

        assertFalse(factory.isCollateralWhitelisted(cbbtc));
        assertEq(address(factory.collateralFeeds(cbbtc)), address(0));
    }

    function test_removeCollateralToken_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.removeCollateralToken(cbbtc);
    }

    function test_removeCollateralToken_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.removeCollateralToken(address(0));
    }

    // ─── whitelistPrincipalToken ───────────────────────────────────
    function test_whitelistPrincipalToken_liveFeed() public {
        // USDC/USD feed on Base — chainlinkBtcUsd works as a live feed for probe
        // purposes; production will register a real USDC/USD feed.
        vm.expectEmit(true, true, true, true, address(factory));
        emit PrincipalTokenWhitelisted(usdc, chainlinkBtcUsd);
        vm.prank(temporalGovernor);
        factory.whitelistPrincipalToken(
            usdc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );
        assertTrue(factory.isPrincipalTokenWhitelisted(usdc));
        assertEq(address(factory.principalTokenFeeds(usdc)), chainlinkBtcUsd);
    }

    function test_whitelistPrincipalToken_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.whitelistPrincipalToken(
            usdc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );
    }

    function test_whitelistPrincipalToken_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.whitelistPrincipalToken(
            address(0),
            AggregatorV3Interface(chainlinkBtcUsd)
        );

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.whitelistPrincipalToken(
            usdc,
            AggregatorV3Interface(address(0))
        );
    }

    function test_whitelistPrincipalToken_staleFeedReverts() public {
        address fakeFeed = makeAddr("fakeFeed");
        _mockDecimals(fakeFeed, 8);
        vm.mockCall(
            fakeFeed,
            abi.encodeWithSelector(
                AggregatorV3Interface.latestRoundData.selector
            ),
            abi.encode(
                uint80(0),
                int256(1e8),
                uint256(0),
                block.timestamp - 2 days,
                uint80(0)
            )
        );

        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.StaleOraclePrice.selector);
        factory.whitelistPrincipalToken(usdc, AggregatorV3Interface(fakeFeed));
    }

    // ─── removePrincipalToken ──────────────────────────────────────
    function test_removePrincipalToken_clears() public {
        vm.prank(temporalGovernor);
        factory.whitelistPrincipalToken(
            usdc,
            AggregatorV3Interface(chainlinkBtcUsd)
        );

        vm.expectEmit(true, true, true, true, address(factory));
        emit PrincipalTokenRemoved(usdc);
        vm.prank(temporalGovernor);
        factory.removePrincipalToken(usdc);

        assertFalse(factory.isPrincipalTokenWhitelisted(usdc));
        assertEq(address(factory.principalTokenFeeds(usdc)), address(0));
    }

    function test_removePrincipalToken_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.removePrincipalToken(usdc);
    }

    // ─── setStalenessWindow ────────────────────────────────────────
    function test_setStalenessWindow_updates() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit StalenessWindowUpdated(3_600);
        vm.prank(temporalGovernor);
        factory.setStalenessWindow(3_600);
        assertEq(factory.stalenessWindow(), 3_600);
    }

    function test_setStalenessWindow_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setStalenessWindow(3_600);
    }

    function test_setStalenessWindow_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidStalenessWindow.selector
        );
        factory.setStalenessWindow(0);
    }

    function test_setStalenessWindow_aboveCapReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidStalenessWindow.selector
        );
        factory.setStalenessWindow(7 days + 1);
    }

    // ─── setMinOriginationLtvBufferBps ─────────────────────────────
    function test_setMinOriginationLtvBufferBps_updates() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit MinOriginationLtvBufferBpsUpdated(0, 1_000);
        vm.prank(temporalGovernor);
        factory.setMinOriginationLtvBufferBps(1_000);
        assertEq(factory.minOriginationLtvBufferBps(), 1_000);
    }

    function test_setMinOriginationLtvBufferBps_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setMinOriginationLtvBufferBps(1_000);
    }

    function test_setMinOriginationLtvBufferBps_belowMinReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidBufferBps.selector);
        factory.setMinOriginationLtvBufferBps(99);
    }

    function test_setMinOriginationLtvBufferBps_aboveMaxReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidBufferBps.selector);
        factory.setMinOriginationLtvBufferBps(10_001);
    }

    // ─── setDefaultParams ──────────────────────────────────────────
    function test_setDefaultParams_updates() public {
        vm.expectEmit(true, true, true, true, address(factory));
        emit DefaultParamsUpdated(86_400, 2_000, 2, 500);
        vm.prank(temporalGovernor);
        factory.setDefaultParams(86_400, 2_000, 2, 500);
        assertEq(factory.defaultGracePeriod(), 86_400);
        assertEq(factory.defaultOverSeizureBps(), 2_000);
        assertEq(factory.defaultConsecutiveMissesForDefault(), 2);
        assertEq(factory.defaultMarketplaceFeeBps(), 500);
    }

    function test_setDefaultParams_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setDefaultParams(86_400, 2_000, 2, 500);
    }

    function test_setDefaultParams_gracePeriodTooLongReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.InvalidGracePeriod.selector);
        factory.setDefaultParams(7 days + 1, 2_000, 2, 500);
    }

    function test_setDefaultParams_overSeizureTooHighReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidOverSeizureBps.selector
        );
        factory.setDefaultParams(86_400, 5_001, 2, 500);
    }

    function test_setDefaultParams_zeroMissesReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidConsecutiveMisses.selector
        );
        factory.setDefaultParams(86_400, 2_000, 0, 500);
    }

    function test_setDefaultParams_missesTooHighReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidConsecutiveMisses.selector
        );
        factory.setDefaultParams(86_400, 2_000, 11, 500);
    }

    function test_setDefaultParams_feeBpsTooHighReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(
            CreditMarketplaceFactory.InvalidMarketplaceFeeBps.selector
        );
        factory.setDefaultParams(86_400, 2_000, 2, 2_001);
    }

    // ─── setFeeRecipient ───────────────────────────────────────────
    function test_setFeeRecipient_updates() public {
        address newRecipient = makeAddr("newTreasury");
        vm.expectEmit(true, true, true, true, address(factory));
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        vm.prank(temporalGovernor);
        factory.setFeeRecipient(newRecipient);
        assertEq(factory.feeRecipient(), newRecipient);
    }

    function test_setFeeRecipient_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setFeeRecipient(makeAddr("x"));
    }

    function test_setFeeRecipient_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.setFeeRecipient(address(0));
    }

    // ─── setPauseGuardian ──────────────────────────────────────────
    function test_setPauseGuardian_updatesAndRotatesRole() public {
        address newGuardian = makeAddr("newGuardian");
        vm.expectEmit(true, true, true, true, address(factory));
        emit PauseGuardianUpdated(pauseGuardian, newGuardian);
        vm.prank(temporalGovernor);
        factory.setPauseGuardian(newGuardian);
        assertEq(factory.pauseGuardian(), newGuardian);

        // Old guardian can no longer pause; new one can.
        vm.prank(pauseGuardian);
        vm.expectRevert(CreditMarketplaceFactory.OnlyOwnerOrGuardian.selector);
        factory.pause();

        vm.prank(newGuardian);
        factory.pause();
        assertTrue(factory.paused());
    }

    function test_setPauseGuardian_nonOwnerReverts() public {
        vm.expectRevert(bytes(NOT_OWNER));
        factory.setPauseGuardian(makeAddr("x"));
    }

    function test_setPauseGuardian_zeroReverts() public {
        vm.prank(temporalGovernor);
        vm.expectRevert(CreditMarketplaceFactory.ZeroAddress.selector);
        factory.setPauseGuardian(address(0));
    }

    // ─── isNonceUsed view ──────────────────────────────────────────
    function test_isNonceUsed_defaultsFalse() public view {
        assertFalse(factory.isNonceUsed(lender, 0));
        assertFalse(factory.isNonceUsed(borrower, 123));
        assertFalse(factory.isNonceUsed(backendSignerEOA, type(uint256).max));
    }

    function _mockDecimals(address feed, uint8 d) internal {
        vm.mockCall(
            feed,
            abi.encodeWithSelector(AggregatorV3Interface.decimals.selector),
            abi.encode(d)
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X66: Anthias Labs Monthly Risk Parameters + Reserve
///        Recommendations September 2026
/// @notice In addition to the market updates configured in x66.json (wrsETH
///         collateral factor on Base and Optimism, cbETH collateral factor on
///         Optimism), this proposal executes the September 2026 reserve
///         recommendations: repay bad debt on behalf of insolvent Base
///         accounts, funded from same-market protocol reserves
///         (reduce reserves -> approve -> repayBorrowBehalf, following
///         MIP-X63 / MIP-X61 / MIP-X60).
///
///         Per market: one _reduceReserves for the total, one approve for the
///         total, then one repayBorrowBehalf per borrower.
///
///         Amounts in the forum plan carry more precision than the token
///         decimals for USDC and cbXRP (6 decimals); calldata amounts are
///         rounded to token decimals.
contract mipx66 is MarketUpdateV2Template {
    struct Repayment {
        address borrower;
        uint256 amount;
        string label;
    }

    struct Plan {
        string market;
        uint256 totalReduce;
        Repayment[] repays;
    }

    /// @notice minimum live cash required per market, in basis points of the
    ///         total amount its _reduceReserves action pulls (1.1x buffer)
    uint256 public constant CASH_HEADROOM_BPS = 11_000;

    mapping(address market => uint256 reserves) internal reservesBefore;
    mapping(address market => uint256 index) internal borrowIndexBefore;
    mapping(bytes32 pair => uint256 borrowBalance) internal borrowBefore;

    function name() external pure override returns (string memory) {
        return "MIP-X66";
    }

    function _basePlans() internal pure returns (Plan[] memory p) {
        p = new Plan[](3);

        p[0].market = "MOONWELL_AERO";
        p[0].totalReduce = 10156.7989e18;
        p[0].repays = new Repayment[](1);
        p[0].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            10156.7989e18,
            "10,156.7989 AERO"
        );

        p[1].market = "MOONWELL_USDC";
        p[1].totalReduce = 15931.302199e6;
        p[1].repays = new Repayment[](6);
        p[1].repays[0] = Repayment(
            0x185542374ce5Fc8bF8F215F5Fc681370704fD124,
            4696.141494e6,
            "4,696.141494 USDC"
        );
        p[1].repays[1] = Repayment(
            0xF61D6742Eea5E1f29cb4B96Cf7108F32424d562c,
            4145.514474e6,
            "4,145.514474 USDC"
        );
        p[1].repays[2] = Repayment(
            0x3e2178CF851A0e5cbF84c0ff53f820ad7EAD703b,
            1894.716419e6,
            "1,894.716419 USDC"
        );
        p[1].repays[3] = Repayment(
            0x76e5db63BF8F1F22886EBe88fB4ed6859b36B6cD,
            1836.62271e6,
            "1,836.622710 USDC"
        );
        p[1].repays[4] = Repayment(
            0x8c40a7D8C37B30C8A4B228CA0885E65444A676a0,
            1687.784139e6,
            "1,687.784139 USDC"
        );
        p[1].repays[5] = Repayment(
            0xe811980cD6A377796c4cC35f6D3A2362cbEFe697,
            1670.522963e6,
            "1,670.522963 USDC"
        );

        p[2].market = "MOONWELL_cbXRP";
        p[2].totalReduce = 1511.4108e6;
        p[2].repays = new Repayment[](1);
        p[2].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            1511.4108e6,
            "1,511.4108 cbXRP"
        );
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);
        Plan[] memory basePlans = _basePlans();
        for (uint256 i = 0; i < basePlans.length; i++) {
            _pushPlan(addresses, basePlans[i], ActionType.Base, "Base");
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);
        _snapshotPlans(addresses, _basePlans());
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);
        _validatePlans(addresses, _basePlans());
    }

    /// @notice push reduce -> approve -> repay actions for one market's
    ///         repayment plan. Assumes the plan's chain fork is selected so
    ///         underlying() reads resolve.
    function _pushPlan(
        Addresses addresses,
        Plan memory plan,
        ActionType actionType,
        string memory chainLabel
    ) internal {
        uint256 repaySum;
        for (uint256 i = 0; i < plan.repays.length; i++) {
            repaySum += plan.repays[i].amount;
        }
        require(
            repaySum == plan.totalReduce,
            string.concat(
                "repayments do not sum to reduce total on ",
                plan.market
            )
        );

        address market = addresses.getAddress(plan.market);
        address underlying = MErc20(market).underlying();

        _pushAction(
            market,
            abi.encodeWithSignature(
                "_reduceReserves(uint256)",
                plan.totalReduce
            ),
            string.concat(
                "Reduce reserves of ",
                plan.market,
                " on ",
                chainLabel
            ),
            actionType
        );

        _pushAction(
            underlying,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                market,
                plan.totalReduce
            ),
            string.concat("Approve ", plan.market, " to pull repaid reserves"),
            actionType
        );

        for (uint256 i = 0; i < plan.repays.length; i++) {
            _pushAction(
                market,
                abi.encodeWithSignature(
                    "repayBorrowBehalf(address,uint256)",
                    plan.repays[i].borrower,
                    plan.repays[i].amount
                ),
                string.concat(
                    "Repay ",
                    plan.repays[i].label,
                    " on behalf of ",
                    vm.toString(plan.repays[i].borrower),
                    " on ",
                    plan.market
                ),
                actionType
            );
        }
    }

    /// @notice snapshot pre-execution state and assert the plan is executable
    ///         at fork state: borrowers still owe at least the repay amount,
    ///         reserves cover the reduction, and live cash has 1.1x headroom.
    function _snapshotPlans(Addresses addresses, Plan[] memory plans) internal {
        for (uint256 i = 0; i < plans.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(plans[i].market));

            for (uint256 j = 0; j < plans[i].repays.length; j++) {
                Repayment memory rec = plans[i].repays[j];

                uint256 borrowBalance = market.borrowBalanceStored(
                    rec.borrower
                );

                assertGe(
                    borrowBalance,
                    rec.amount,
                    string.concat(
                        "borrow balance below repay amount for ",
                        vm.toString(rec.borrower),
                        " on ",
                        plans[i].market
                    )
                );

                borrowBefore[
                    keccak256(abi.encodePacked(address(market), rec.borrower))
                ] = borrowBalance;
            }

            reservesBefore[address(market)] = market.totalReserves();
            borrowIndexBefore[address(market)] = market.borrowIndex();

            assertGe(
                market.totalReserves(),
                plans[i].totalReduce,
                string.concat(
                    "insufficient reserves to execute _reduceReserves on ",
                    plans[i].market
                )
            );

            assertGe(
                market.getCash(),
                (plans[i].totalReduce * CASH_HEADROOM_BPS) / 10_000,
                string.concat("cash headroom below 1.1x on ", plans[i].market)
            );
        }
    }

    function _validatePlans(
        Addresses addresses,
        Plan[] memory plans
    ) internal view {
        address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");

        for (uint256 i = 0; i < plans.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(plans[i].market));

            for (uint256 j = 0; j < plans[i].repays.length; j++) {
                _assertRepayEffects(
                    market,
                    plans[i].market,
                    plans[i].repays[j]
                );
            }

            _assertReservesDown(market, plans[i].market, plans[i].totalReduce);

            assertEq(
                IERC20(market.underlying()).allowance(tempGov, address(market)),
                0,
                string.concat(
                    "allowance not fully consumed on ",
                    plans[i].market
                )
            );
        }
    }

    /// @notice the harness warps days of interest accrual between the
    ///         beforeSimulationHook snapshot and validate, so raw
    ///         before/after borrow comparisons are meaningless for accounts
    ///         whose accrued interest can outpace the repaid amount. Compare
    ///         against the no-repay counterfactual instead: scale the
    ///         snapshot by borrowIndex growth, then require the shortfall vs
    ///         that counterfactual to equal the repaid amount (the repaid
    ///         principal itself keeps accruing after execution, so the
    ///         shortfall lands in [amount, amount * indexGrowth]). 1 bps
    ///         tolerance on each side absorbs borrowBalanceStored rounding.
    function _assertRepayEffects(
        MErc20 market,
        string memory marketName,
        Repayment memory rec
    ) internal view {
        uint256 borrowBalanceBefore = borrowBefore[
            keccak256(abi.encodePacked(address(market), rec.borrower))
        ];
        uint256 borrowBalanceAfter = market.borrowBalanceStored(rec.borrower);

        uint256 indexBefore = borrowIndexBefore[address(market)];
        uint256 counterfactual = (borrowBalanceBefore * market.borrowIndex()) /
            indexBefore;

        assertLt(
            borrowBalanceAfter,
            counterfactual,
            string.concat(
                "borrow balance did not decrease vs accrual counterfactual for ",
                vm.toString(rec.borrower),
                " on ",
                marketName
            )
        );

        uint256 borrowDecrease = counterfactual - borrowBalanceAfter;
        assertGe(
            borrowDecrease,
            (rec.amount * 9_999) / 10_000,
            string.concat(
                "borrow decrease below repaid amount for ",
                vm.toString(rec.borrower),
                " on ",
                marketName
            )
        );
        assertLe(
            borrowDecrease,
            (((rec.amount * market.borrowIndex()) / indexBefore) * 10_001) /
                10_000,
            string.concat(
                "borrow decrease exceeds repaid amount plus accrual for ",
                vm.toString(rec.borrower),
                " on ",
                marketName
            )
        );
    }

    /// @notice reserves accrue interest during the harness's governance
    ///         warps, so totalReserves can net-INCREASE across execution when
    ///         accrual outpaces the reduction (observed on USDC). Only bound
    ///         the net decrease: it must never exceed the reduced amount.
    ///         Execution of the reduce itself is proven by the repayments
    ///         (funded solely by it) and the fully-consumed allowance.
    function _assertReservesDown(
        MErc20 market,
        string memory marketName,
        uint256 expected
    ) internal view {
        assertGe(
            market.totalReserves() + expected,
            reservesBefore[address(market)],
            string.concat("reserves decrease exceeds target on ", marketName)
        );
    }
}

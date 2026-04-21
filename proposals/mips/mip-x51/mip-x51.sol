//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {RewardsDistributionTemplate} from "@proposals/templates/RewardsDistribution.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X51
/// @notice Rewards distribution with additional bad-debt repayments on Base.
///         Extends RewardsDistributionTemplate and appends, as Base actions:
///           - reduce reserves from a market
///           - approve the market to spend the underlying
///           - repayBorrowBehalf for a specific borrower
contract mipx51 is RewardsDistributionTemplate {
    // Borrowers whose debt is being repaid
    address internal constant VIRTUAL_BORROWER =
        0xA98E339f5a0F135792286d481B4e23d91A667d3f;
    address internal constant CBXRP_USDC_BORROWER =
        0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB;
    address internal constant CBETH_BORROWER =
        0x9E81B20E3255CdFAeBDA41d5dECBACd9fc6aE0a9;

    // Amounts (underlying decimals): VIRTUAL=18, cbXRP=6, USDC=6, cbETH=18
    uint256 internal constant VIRTUAL_AMOUNT = 953_335 * 1e18;
    uint256 internal constant CBXRP_AMOUNT = 522_946_300_000; // 522,946.30 * 1e6
    uint256 internal constant USDC_AMOUNT = 81_844_160_000; // 81,844.16 * 1e6
    uint256 internal constant CBETH_AMOUNT = 59_145_900_000_000_000_000; // 59.1459 * 1e18

    // Per-market state captured before simulation so validate() can diff.
    struct MarketSnapshot {
        uint256 totalReserves;
        uint256 cash;
        uint256 temporalGovUnderlyingBalance;
        uint256 borrowBalance;
    }
    mapping(address => MarketSnapshot) internal snapshotBefore;
    mapping(address => address) internal snapshotBorrower;

    function name() external pure override returns (string memory) {
        return "MIP-X51";
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);

        _pushBadDebtRepay(
            addresses,
            "MOONWELL_VIRTUAL",
            VIRTUAL_BORROWER,
            VIRTUAL_AMOUNT,
            "953,335.00 VIRTUAL"
        );

        _pushBadDebtRepay(
            addresses,
            "MOONWELL_cbXRP",
            CBXRP_USDC_BORROWER,
            CBXRP_AMOUNT,
            "522,946.30 cbXRP"
        );

        _pushBadDebtRepay(
            addresses,
            "MOONWELL_USDC",
            CBXRP_USDC_BORROWER,
            USDC_AMOUNT,
            "81,844.16 USDC"
        );

        _pushBadDebtRepay(
            addresses,
            "MOONWELL_cbETH",
            CBETH_BORROWER,
            CBETH_AMOUNT,
            "59.1459 cbETH"
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);

        _assertRepayEffects(addresses, "MOONWELL_VIRTUAL", VIRTUAL_AMOUNT);
        _assertRepayEffects(addresses, "MOONWELL_cbXRP", CBXRP_AMOUNT);
        _assertRepayEffects(addresses, "MOONWELL_USDC", USDC_AMOUNT);
        _assertRepayEffects(addresses, "MOONWELL_cbETH", CBETH_AMOUNT);
    }

    /// @dev snapshot per-market state before simulation so validate() can
    ///      assert the 3-step reduce/approve/repay sequence took effect.
    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);

        _snapshot(addresses, "MOONWELL_VIRTUAL", VIRTUAL_BORROWER);
        _snapshot(addresses, "MOONWELL_cbXRP", CBXRP_USDC_BORROWER);
        _snapshot(addresses, "MOONWELL_USDC", CBXRP_USDC_BORROWER);
        _snapshot(addresses, "MOONWELL_cbETH", CBETH_BORROWER);
    }

    function _pushBadDebtRepay(
        Addresses addresses,
        string memory marketName,
        address borrower,
        uint256 amount,
        string memory amountLabel
    ) internal {
        address market = addresses.getAddress(marketName);
        address underlying = MErc20(market).underlying();

        _pushAction(
            market,
            abi.encodeWithSignature("_reduceReserves(uint256)", amount),
            string.concat(
                "Reduce reserves of ",
                amountLabel,
                " from ",
                marketName,
                " on Base"
            ),
            ActionType.Base
        );

        _pushAction(
            underlying,
            abi.encodeWithSignature("approve(address,uint256)", market, amount),
            string.concat("Approve ", marketName, " to pull ", amountLabel),
            ActionType.Base
        );

        // These repays are intentionally PARTIAL: `amount` is the reserve
        // portion we can pull, not the borrower's full outstanding balance
        // (which is materially larger). The Compound uint256.max sentinel
        // would clip to the full accountBorrows and then fail with
        // insufficient allowance/balance because we only pulled `amount`
        // from reserves. The alternative subUInt-underflow race flagged by
        // the audit (debt < amount before execution) would require a third
        // party to repay the spread between the on-chain debt and `amount`
        // — implausible for bad-debt positions.
        _pushAction(
            market,
            abi.encodeWithSignature(
                "repayBorrowBehalf(address,uint256)",
                borrower,
                amount
            ),
            string.concat(
                "Repay ",
                amountLabel,
                " on behalf of ",
                vm.toString(borrower),
                " on ",
                marketName
            ),
            ActionType.Base
        );
    }

    function _snapshot(
        Addresses addresses,
        string memory marketName,
        address borrower
    ) internal {
        MErc20 market = MErc20(addresses.getAddress(marketName));
        IERC20 underlying = IERC20(market.underlying());
        address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");

        snapshotBorrower[address(market)] = borrower;
        snapshotBefore[address(market)] = MarketSnapshot({
            totalReserves: market.totalReserves(),
            cash: market.getCash(),
            temporalGovUnderlyingBalance: underlying.balanceOf(tempGov),
            borrowBalance: market.borrowBalanceStored(borrower)
        });
    }

    /// @dev Assert invariants of the reduce → approve → repay sequence:
    ///        1. totalReserves decreased (reduce executed)
    ///        2. borrower's borrow balance decreased (repay executed)
    ///        3. residual allowance ≤ approved amount (no over-approval leak)
    ///        4. totalReserves decrease is in the neighbourhood of `amount`
    ///           (the only way reservesDown drifts is interest accrual during
    ///           the vote/queue/execute warp — ±15% is wide enough to cover
    ///           multi-week warps in any harness while still catching a
    ///           reduce that didn't execute, a double-reduce, etc.)
    ///
    /// A tighter equality between reservesDown, borrowDown and tempGovUp
    /// would catch a stronger class of bugs but depends on the specific
    /// number of warps each PostProposalCheck consumer runs before us —
    /// unstable across harnesses.
    function _assertRepayEffects(
        Addresses addresses,
        string memory marketName,
        uint256 amount
    ) internal {
        MErc20 market = MErc20(addresses.getAddress(marketName));
        IERC20 underlying = IERC20(market.underlying());
        address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");
        address borrower = snapshotBorrower[address(market)];
        MarketSnapshot memory s = snapshotBefore[address(market)];

        assertLt(
            market.totalReserves(),
            s.totalReserves,
            string.concat("totalReserves did not decrease on ", marketName)
        );

        assertLt(
            market.borrowBalanceStored(borrower),
            s.borrowBalance,
            string.concat("borrow balance did not decrease on ", marketName)
        );

        assertLe(
            underlying.allowance(tempGov, address(market)),
            amount,
            string.concat("allowance exceeds approved amount on ", marketName)
        );

        uint256 reservesDown = s.totalReserves - market.totalReserves();
        assertApproxEqRel(
            reservesDown,
            amount,
            0.15e18,
            string.concat("reserves decrease far from target on ", marketName)
        );
    }
}

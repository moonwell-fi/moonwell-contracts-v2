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

    // Borrow balances captured before simulation so we can verify repayment effects.
    mapping(address => mapping(address => uint256))
        internal borrowBalanceBefore;

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

        _assertRepaid(
            addresses,
            "MOONWELL_VIRTUAL",
            VIRTUAL_BORROWER,
            VIRTUAL_AMOUNT
        );
        _assertRepaid(
            addresses,
            "MOONWELL_cbXRP",
            CBXRP_USDC_BORROWER,
            CBXRP_AMOUNT
        );
        _assertRepaid(
            addresses,
            "MOONWELL_USDC",
            CBXRP_USDC_BORROWER,
            USDC_AMOUNT
        );
        _assertRepaid(
            addresses,
            "MOONWELL_cbETH",
            CBETH_BORROWER,
            CBETH_AMOUNT
        );
    }

    /// @dev snapshot borrower debt before repayment so validate() can diff.
    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);

        _snapshotBorrow(addresses, "MOONWELL_VIRTUAL", VIRTUAL_BORROWER);
        _snapshotBorrow(addresses, "MOONWELL_cbXRP", CBXRP_USDC_BORROWER);
        _snapshotBorrow(addresses, "MOONWELL_USDC", CBXRP_USDC_BORROWER);
        _snapshotBorrow(addresses, "MOONWELL_cbETH", CBETH_BORROWER);
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

    function _snapshotBorrow(
        Addresses addresses,
        string memory marketName,
        address borrower
    ) internal {
        MErc20 market = MErc20(addresses.getAddress(marketName));
        borrowBalanceBefore[address(market)][borrower] = market
            .borrowBalanceStored(borrower);
    }

    function _assertRepaid(
        Addresses addresses,
        string memory marketName,
        address borrower,
        uint256 amount
    ) internal {
        MErc20 market = MErc20(addresses.getAddress(marketName));
        uint256 before = borrowBalanceBefore[address(market)][borrower];
        uint256 current = market.borrowBalanceStored(borrower);

        // interest may have accrued; require at least `amount` was reduced from the
        // pre-proposal balance, allowing for a small accrual tolerance.
        assertLe(
            current + amount,
            before + (before / 1000), // +0.1% tolerance for accrued interest
            string.concat(
                "Repay did not reduce borrow balance by expected amount on ",
                marketName
            )
        );
    }
}

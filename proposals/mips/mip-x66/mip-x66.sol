//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @title MIP-X66: Anthias Labs Urgent Risk Parameter Recommendations
///        (8/29/26)
/// @notice Two workstreams:
///         1. Market updates configured in x66.json (collateral factors,
///            reserve factors, and interest rate model replacements on Base
///            and Optimism). The supply/borrow cap changes from the same
///            recommendation are executed separately by the Cap Guardian.
///         2. Reserve withdrawals for USDC-market recapitalization: reduce
///            each market's withdrawable reserves and transfer the underlying
///            to the operations wallet, which swaps to USDC and repays on
///            behalf of the insolvent account off-chain (steps 2-3 of the
///            Anthias reserves summary — swaps cannot be executed reliably
///            through a multi-day governance timelock).
///
///         Withdrawal amounts follow the report's "Withdrawable now" table,
///         clamped to live totalReserves where accrual rounding left the
///         table a hair above the on-chain value (Base DAI, OP DAI, OP
///         weETH). Three Base legs from the report are dropped because their
///         market cash drained to dust after the 8/29 snapshot (EURC, MAMO,
///         USDS); their reserves stay accounted and can be recovered by a
///         later proposal once liquidity returns.
contract mipx66 is MarketUpdateV2Template {
    struct Withdrawal {
        uint256 amount;
        string market;
    }

    /// @notice operations wallet receiving all withdrawn reserves on both
    ///         chains (swap-to-USDC + repayBorrowBehalf happen off-chain)
    address public constant RESERVES_RECIPIENT =
        0x9917Ea34179D87F06C8b9D4AfB8BD78248B434ef;

    /// @notice minimum live cash required per market, in basis points of the
    ///         amount its _reduceReserves action pays out (1.1x buffer)
    uint256 public constant CASH_HEADROOM_BPS = 11_000;

    mapping(uint256 chainId => mapping(address market => uint256 reserves))
        internal reservesBefore;
    mapping(uint256 chainId => mapping(address underlying => uint256 balance))
        internal recipientBalanceBefore;

    function name() external pure override returns (string memory) {
        return "MIP-X66";
    }

    function _baseWithdrawals() internal pure returns (Withdrawal[] memory w) {
        w = new Withdrawal[](16);
        w[0] = Withdrawal(13933955658000000000000, "MOONWELL_AERO");
        w[1] = Withdrawal(14127886, "MOONWELL_cbBTC");
        w[2] = Withdrawal(1973306139, "MOONWELL_cbXRP");
        w[3] = Withdrawal(750993041658567397228, "MOONWELL_DAI");
        w[4] = Withdrawal(47675, "MOONWELL_LBTC");
        w[5] = Withdrawal(120805139000000000000, "MOONWELL_MORPHO");
        w[6] = Withdrawal(608231062000000000, "MOONWELL_rETH");
        w[7] = Withdrawal(75664422000000000, "MOONWELL_TBTC");
        w[8] = Withdrawal(4501868, "MOONWELL_USDBC");
        w[9] = Withdrawal(1366630495000000000000, "MOONWELL_VIRTUAL");
        w[10] = Withdrawal(1593758590000000000000, "MOONWELL_VVV");
        w[11] = Withdrawal(51625392000000000, "MOONWELL_weETH");
        w[12] = Withdrawal(2930209091257000000000000, "MOONWELL_WELL");
        w[13] = Withdrawal(1109038511000000000, "MOONWELL_WETH");
        w[14] = Withdrawal(1187732247000000000, "MOONWELL_wrsETH");
        w[15] = Withdrawal(392644076000000000, "MOONWELL_wstETH");
    }

    function _opWithdrawals() internal pure returns (Withdrawal[] memory w) {
        w = new Withdrawal[](11);
        w[0] = Withdrawal(1786704977808464158454, "MOONWELL_DAI");
        w[1] = Withdrawal(13367564019000000000000, "MOONWELL_OP");
        w[2] = Withdrawal(65486702170, "MOONWELL_USDC");
        w[3] = Withdrawal(9517375163, "MOONWELL_USDT");
        w[4] = Withdrawal(3280633869, "MOONWELL_USDT0");
        w[5] = Withdrawal(593943920606000000000000, "MOONWELL_VELO");
        w[6] = Withdrawal(7519, "MOONWELL_WBTC");
        w[7] = Withdrawal(159985966730346507, "MOONWELL_weETH");
        w[8] = Withdrawal(31040076475000000000, "MOONWELL_WETH");
        w[9] = Withdrawal(147359358000000000, "MOONWELL_wrsETH");
        w[10] = Withdrawal(729228476000000000, "MOONWELL_wstETH");
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);
        _pushWithdrawals(
            addresses,
            _baseWithdrawals(),
            ActionType.Base,
            "Base"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        _pushWithdrawals(
            addresses,
            _opWithdrawals(),
            ActionType.Optimism,
            "Optimism"
        );
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);
        _snapshotWithdrawals(addresses, _baseWithdrawals());

        vm.selectFork(OPTIMISM_FORK_ID);
        _snapshotWithdrawals(addresses, _opWithdrawals());
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);
        _validateWithdrawals(addresses, _baseWithdrawals());

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateWithdrawals(addresses, _opWithdrawals());
    }

    /// @notice push reduce -> transfer actions for one chain's withdrawal
    ///         plan. Assumes the plan's fork is selected so underlying()
    ///         reads resolve.
    ///
    ///         WETH markets need special handling because MWethDelegate's
    ///         doTransferOut unwraps to native ETH:
    ///         - Base: the market's admin is MWETH_OWNER_WRAPPER (owned by
    ///           the Temporal Governor), which auto-wraps the received ETH;
    ///           reduce through it, then withdrawToken the WETH straight to
    ///           the recipient (MIP-X60/X61 precedent).
    ///         - Optimism: the market's admin is the Temporal Governor
    ///           itself, which receives NATIVE ETH via the WethUnwrapper; a
    ///           plain value-transfer action forwards it to the recipient.
    function _pushWithdrawals(
        Addresses addresses,
        Withdrawal[] memory plan,
        ActionType actionType,
        string memory chainLabel
    ) internal {
        for (uint256 i = 0; i < plan.length; i++) {
            address market = addresses.getAddress(plan[i].market);
            address underlying = MErc20(market).underlying();

            bool isWeth = keccak256(abi.encodePacked(plan[i].market)) ==
                keccak256(abi.encodePacked("MOONWELL_WETH"));
            bool hasWrapper = addresses.isAddressSet("MWETH_OWNER_WRAPPER");

            address reduceTarget = isWeth && hasWrapper
                ? addresses.getAddress("MWETH_OWNER_WRAPPER")
                : market;

            _pushAction(
                reduceTarget,
                abi.encodeWithSignature(
                    "_reduceReserves(uint256)",
                    plan[i].amount
                ),
                string.concat(
                    "Reduce reserves of ",
                    plan[i].market,
                    " on ",
                    chainLabel
                ),
                actionType
            );

            if (isWeth && hasWrapper) {
                _pushAction(
                    reduceTarget,
                    abi.encodeWithSignature(
                        "withdrawToken(address,address,uint256)",
                        underlying,
                        RESERVES_RECIPIENT,
                        plan[i].amount
                    ),
                    string.concat(
                        "Withdraw wrapped WETH reserves from ",
                        "MWETH_OWNER_WRAPPER to the operations wallet"
                    ),
                    actionType
                );
            } else if (isWeth) {
                _pushAction(
                    RESERVES_RECIPIENT,
                    plan[i].amount,
                    "",
                    string.concat(
                        "Forward withdrawn native ETH reserves to the ",
                        "operations wallet on ",
                        chainLabel
                    ),
                    actionType
                );
            } else {
                _pushAction(
                    underlying,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        RESERVES_RECIPIENT,
                        plan[i].amount
                    ),
                    string.concat(
                        "Transfer withdrawn ",
                        plan[i].market,
                        " reserves to the operations wallet"
                    ),
                    actionType
                );
            }
        }
    }

    /// @notice snapshot pre-execution state and assert the plan is
    ///         executable at fork state: reserves cover the reduction and
    ///         live cash has 1.1x headroom (a fully-utilized market fails
    ///         _reduceReserves with TOKEN_INSUFFICIENT_CASH, which is why the
    ///         drained EURC/MAMO/USDS legs were dropped).
    function _snapshotWithdrawals(
        Addresses addresses,
        Withdrawal[] memory plan
    ) internal {
        for (uint256 i = 0; i < plan.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(plan[i].market));
            address underlying = market.underlying();

            assertGe(
                market.totalReserves(),
                plan[i].amount,
                string.concat(
                    "insufficient reserves to withdraw on ",
                    plan[i].market
                )
            );
            assertGe(
                market.getCash(),
                (plan[i].amount * CASH_HEADROOM_BPS) / 10_000,
                string.concat("cash headroom below 1.1x on ", plan[i].market)
            );

            reservesBefore[block.chainid][address(market)] = market
                .totalReserves();
            recipientBalanceBefore[block.chainid][
                underlying
            ] = _recipientBalance(addresses, plan[i].market, underlying);
        }
    }

    /// @notice the recipient's balance in whatever asset a market's
    ///         withdrawal actually delivers: native ETH for a WETH market
    ///         without an owner wrapper (Optimism), the ERC20 otherwise
    function _recipientBalance(
        Addresses addresses,
        string memory marketName,
        address underlying
    ) internal view returns (uint256) {
        bool nativeDelivery = keccak256(abi.encodePacked(marketName)) ==
            keccak256(abi.encodePacked("MOONWELL_WETH")) &&
            !addresses.isAddressSet("MWETH_OWNER_WRAPPER");

        return
            nativeDelivery
                ? RESERVES_RECIPIENT.balance
                : IERC20(underlying).balanceOf(RESERVES_RECIPIENT);
    }

    /// @notice the recipient's exact balance delta proves both legs executed
    ///         (the silent-error-code _reduceReserves funded the
    ///         TemporalGovernor, and the transfer moved the full amount out).
    ///         Reserves accrue interest during the harness's governance
    ///         warps, so only bound the net decrease.
    function _validateWithdrawals(
        Addresses addresses,
        Withdrawal[] memory plan
    ) internal view {
        for (uint256 i = 0; i < plan.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(plan[i].market));
            address underlying = market.underlying();

            assertEq(
                _recipientBalance(addresses, plan[i].market, underlying),
                recipientBalanceBefore[block.chainid][underlying] +
                    plan[i].amount,
                string.concat(
                    "operations wallet did not receive the withdrawn ",
                    plan[i].market,
                    " reserves"
                )
            );

            assertGe(
                market.totalReserves() + plan[i].amount,
                reservesBefore[block.chainid][address(market)],
                string.concat(
                    "reserves decrease exceeds target on ",
                    plan[i].market
                )
            );
        }
    }
}

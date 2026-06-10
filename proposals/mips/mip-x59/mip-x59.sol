//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MarketUpdateTemplate} from "@proposals/templates/MarketUpdate.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X59: Reserve Recommendations June 2026
/// @notice In addition to the market updates configured in x59.json, this
///         proposal executes two remediation initiatives on Base:
///         1. Repay ~$550K of bad debt on behalf of addresses supplying no
///            collateral, funded from protocol reserves
///            (reduce reserves -> approve -> repayBorrowBehalf, following
///            MIP-X51C).
///         2. Withdraw 1.45 cbBTC from reserves and transfer it to the
///            FOUNDATION_MULTISIG to be swapped to WETH for the next round
///            of cbETH incident remediation (following MIP-B52).
contract mipx59 is MarketUpdateTemplate {
    struct Repayment {
        string market;
        address borrower;
        uint256 amount;
        string label;
    }

    /// @notice cbBTC withdrawn for the cbETH remediation swap (8 decimals)
    uint256 public constant CBBTC_WITHDRAW_AMOUNT = 1.45e8;

    /// @notice expected total reserve decrease per market, used in validate()
    uint256 public constant WETH_RESERVES_DOWN = 74.4075e18;
    uint256 public constant AERO_RESERVES_DOWN = 305721.6534e18;
    uint256 public constant WSTETH_RESERVES_DOWN = 35.6428e18;
    uint256 public constant USDC_RESERVES_DOWN = 69573.3004e6;
    uint256 public constant MORPHO_RESERVES_DOWN = 14771.2359e18;
    uint256 public constant EURC_RESERVES_DOWN = 25767.0938e6;
    uint256 public constant VIRTUAL_RESERVES_DOWN = 16652.5804e18;
    uint256 public constant CBBTC_RESERVES_DOWN = 0.2730562e8 + 1.45e8;

    /// @notice minimum live cash required per market, in basis points of the
    ///         total amount its _reduceReserves actions pull (1.1x buffer)
    uint256 public constant CASH_HEADROOM_BPS = 11_000;

    mapping(address market => uint256 reserves) internal reservesBefore;
    mapping(bytes32 pair => uint256 borrowBalance) internal borrowBefore;
    uint256 internal foundationCbBtcBefore;

    function name() external pure override returns (string memory) {
        return "MIP-X59";
    }

    function _repayments() internal pure returns (Repayment[] memory r) {
        r = new Repayment[](11);
        r[0] = Repayment(
            "MOONWELL_WETH",
            0x3B87f7D473550ef9e53e46Baae856608f8b8A0C4,
            74.4075e18,
            "74.4075 WETH"
        );
        r[1] = Repayment(
            "MOONWELL_AERO",
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            262817.3242e18,
            "262,817.3242 AERO"
        );
        r[2] = Repayment(
            "MOONWELL_wstETH",
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            35.6428e18,
            "35.6428 wstETH"
        );
        r[3] = Repayment(
            "MOONWELL_USDC",
            0xEDB0C9BBEe5A799340480EFc31C0E07Cad54d646,
            43865.80597e6,
            "43,865.80597 USDC"
        );
        r[4] = Repayment(
            "MOONWELL_MORPHO",
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            14771.2359e18,
            "14,771.2359 MORPHO"
        );
        r[5] = Repayment(
            "MOONWELL_EURC",
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            25767.0938e6,
            "25,767.0938 EURC"
        );
        r[6] = Repayment(
            "MOONWELL_USDC",
            0x8c40a7D8C37B30C8A4B228CA0885E65444A676a0,
            25707.49443e6,
            "25,707.49443 USDC"
        );
        r[7] = Repayment(
            "MOONWELL_AERO",
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            42904.3292e18,
            "42,904.3292 AERO"
        );
        r[8] = Repayment(
            "MOONWELL_VIRTUAL",
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            16652.5804e18,
            "16,652.5804 VIRTUAL"
        );
        r[9] = Repayment(
            "MOONWELL_cbBTC",
            0x6A8ee608D88DB389796B9c02A1aaa36b89AC660c,
            0.14764634e8,
            "0.14764634 cbBTC"
        );
        r[10] = Repayment(
            "MOONWELL_cbBTC",
            0x5877022fe1a776E5275eD535b50d83A69634089C,
            0.12540986e8,
            "0.12540986 cbBTC"
        );
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            _pushBadDebtRepay(addresses, repayments[i]);
        }

        // cbETH remediation: withdraw 1.45 cbBTC from reserves and send it to
        // the Foundation multisig to be swapped to WETH for distribution
        address moonwellCbBtc = addresses.getAddress("MOONWELL_cbBTC");

        _pushAction(
            moonwellCbBtc,
            abi.encodeWithSignature(
                "_reduceReserves(uint256)",
                CBBTC_WITHDRAW_AMOUNT
            ),
            "Reduce 1.45 cbBTC reserves from MOONWELL_cbBTC for the cbETH remediation swap",
            ActionType.Base
        );

        _pushAction(
            MErc20(moonwellCbBtc).underlying(),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.getAddress("FOUNDATION_MULTISIG"),
                CBBTC_WITHDRAW_AMOUNT
            ),
            "Transfer 1.45 cbBTC to FOUNDATION_MULTISIG to be swapped to WETH",
            ActionType.Base
        );
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(repayments[i].market));

            reservesBefore[address(market)] = market.totalReserves();
            borrowBefore[
                keccak256(
                    abi.encodePacked(address(market), repayments[i].borrower)
                )
            ] = market.borrowBalanceStored(repayments[i].borrower);
        }

        foundationCbBtcBefore = IERC20(
            MErc20(addresses.getAddress("MOONWELL_cbBTC")).underlying()
        ).balanceOf(addresses.getAddress("FOUNDATION_MULTISIG"));

        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_WETH",
            WETH_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_AERO",
            AERO_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_wstETH",
            WSTETH_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_USDC",
            USDC_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_MORPHO",
            MORPHO_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_EURC",
            EURC_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_VIRTUAL",
            VIRTUAL_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_cbBTC",
            CBBTC_RESERVES_DOWN
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            _assertRepayEffects(addresses, repayments[i]);
        }

        _assertReservesDown(addresses, "MOONWELL_WETH", WETH_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_AERO", AERO_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_wstETH", WSTETH_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_USDC", USDC_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_MORPHO", MORPHO_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_EURC", EURC_RESERVES_DOWN);
        _assertReservesDown(
            addresses,
            "MOONWELL_VIRTUAL",
            VIRTUAL_RESERVES_DOWN
        );
        _assertReservesDown(addresses, "MOONWELL_cbBTC", CBBTC_RESERVES_DOWN);

        // cbETH remediation transfer is exact
        uint256 foundationCbBtcAfter = IERC20(
            MErc20(addresses.getAddress("MOONWELL_cbBTC")).underlying()
        ).balanceOf(addresses.getAddress("FOUNDATION_MULTISIG"));
        assertEq(
            foundationCbBtcAfter - foundationCbBtcBefore,
            CBBTC_WITHDRAW_AMOUNT,
            "FOUNDATION_MULTISIG did not receive 1.45 cbBTC"
        );
    }

    function _pushBadDebtRepay(
        Addresses addresses,
        Repayment memory rec
    ) internal {
        address market = addresses.getAddress(rec.market);
        address underlying = MErc20(market).underlying();

        // MOONWELL_WETH's admin is the MWETH_OWNER_WRAPPER (owned by the
        // Temporal Governor): reserves must be reduced through it, and the
        // auto-wrapped WETH it accumulates withdrawn back to the Temporal
        // Governor before the approve/repay pair
        bool isWeth = keccak256(abi.encodePacked(rec.market)) ==
            keccak256(abi.encodePacked("MOONWELL_WETH"));

        address reduceTarget = isWeth
            ? addresses.getAddress("MWETH_OWNER_WRAPPER")
            : market;

        _pushAction(
            reduceTarget,
            abi.encodeWithSignature("_reduceReserves(uint256)", rec.amount),
            string.concat(
                "Reduce reserves of ",
                rec.label,
                " from ",
                rec.market,
                " on Base"
            ),
            ActionType.Base
        );

        if (isWeth) {
            _pushAction(
                reduceTarget,
                abi.encodeWithSignature(
                    "withdrawToken(address,address,uint256)",
                    underlying,
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    rec.amount
                ),
                string.concat(
                    "Withdraw ",
                    rec.label,
                    " from MWETH_OWNER_WRAPPER to the Temporal Governor"
                ),
                ActionType.Base
            );
        }

        _pushAction(
            underlying,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                market,
                rec.amount
            ),
            string.concat("Approve ", rec.market, " to pull ", rec.label),
            ActionType.Base
        );

        _pushAction(
            market,
            abi.encodeWithSignature(
                "repayBorrowBehalf(address,uint256)",
                rec.borrower,
                rec.amount
            ),
            string.concat(
                "Repay ",
                rec.label,
                " on behalf of ",
                vm.toString(rec.borrower),
                " on ",
                rec.market
            ),
            ActionType.Base
        );
    }

    function _assertRepayEffects(
        Addresses addresses,
        Repayment memory rec
    ) internal view {
        MErc20 market = MErc20(addresses.getAddress(rec.market));
        IERC20 underlying = IERC20(market.underlying());
        address tempGov = addresses.getAddress("TEMPORAL_GOVERNOR");

        uint256 borrowBalanceBefore = borrowBefore[
            keccak256(abi.encodePacked(address(market), rec.borrower))
        ];
        uint256 borrowBalanceAfter = market.borrowBalanceStored(rec.borrower);

        assertLt(
            borrowBalanceAfter,
            borrowBalanceBefore,
            string.concat(
                "borrow balance did not decrease for ",
                vm.toString(rec.borrower),
                " on ",
                rec.market
            )
        );

        assertApproxEqRel(
            borrowBalanceBefore - borrowBalanceAfter,
            rec.amount,
            0.02e18,
            string.concat(
                "borrow decrease far from target for ",
                vm.toString(rec.borrower),
                " on ",
                rec.market
            )
        );

        assertEq(
            underlying.allowance(tempGov, address(market)),
            0,
            string.concat("allowance not fully consumed on ", rec.market)
        );
    }

    /// @notice _reduceReserves fails silently (returns an error code, no
    ///         revert) when totalReserves or cash drop below the requested
    ///         amount, after which the paired repayBorrowBehalf reverts and
    ///         rolls back the entire proposal. The reduce amounts are sized
    ///         to ~100% of snapshot reserves, so execution is all-or-nothing
    ///         across every market. Reserves only grow between snapshot and
    ///         execution (interest accrual), but cash can drain. Asserting
    ///         live headroom pre-simulation makes every CI run of this
    ///         pending proposal (PostProposalCheck simulates against fresh
    ///         fork state) fail loudly if drift erodes the margin during the
    ///         voting window, while there is still time to resize, instead
    ///         of the proposal bricking at on-chain execution.
    function _assertExecutionHeadroom(
        Addresses addresses,
        string memory marketName,
        uint256 required
    ) internal view {
        MErc20 market = MErc20(addresses.getAddress(marketName));

        assertGe(
            market.totalReserves(),
            required,
            string.concat(
                "insufficient reserves to execute _reduceReserves on ",
                marketName
            )
        );

        assertGe(
            market.getCash(),
            (required * CASH_HEADROOM_BPS) / 10_000,
            string.concat("cash headroom below 1.1x on ", marketName)
        );
    }

    function _assertReservesDown(
        Addresses addresses,
        string memory marketName,
        uint256 expected
    ) internal view {
        MErc20 market = MErc20(addresses.getAddress(marketName));
        uint256 before = reservesBefore[address(market)];

        assertLt(
            market.totalReserves(),
            before,
            string.concat("totalReserves did not decrease on ", marketName)
        );

        assertApproxEqRel(
            before - market.totalReserves(),
            expected,
            0.02e18,
            string.concat("reserves decrease far from target on ", marketName)
        );
    }
}

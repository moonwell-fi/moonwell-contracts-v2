//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, ETHEREUM_FORK_ID, ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IComptrollerCaps {
    function borrowCapGuardian() external view returns (address);
    function supplyCapGuardian() external view returns (address);
}

/// @title MIP-X61: Reserve Recommendations July 2026
/// @notice In addition to the market updates configured in x61.json, this
///         proposal executes two initiatives on Base:
///         1. Repay ~$35K of bad debt on behalf of addresses supplying no
///            collateral, funded from protocol reserves
///            (reduce reserves -> approve -> repayBorrowBehalf, following
///            MIP-X60).
///         2. Withdraw 0.23 LBTC, 4 rETH, and 7 weETH from reserves and
///            transfer them to the FOUNDATION_MULTISIG to be swapped to WETH
///            for cbETH incident remediation (~$35K / ~21 WETH).
///         And one Ethereum action:
///         3. Transfer supply and borrow cap guardian on Ethereum Comptroller
///            to the Anthias multisig.
contract mipx61 is MarketUpdateV2Template {
    struct Repayment {
        string market;
        address borrower;
        uint256 amount;
        string label;
    }

    /// @notice new cap guardian address (Anthias multisig)
    address internal constant NEW_CAP_GUARDIAN =
        0x08eDEbFFaE68970DCf751baa826182b3a4aCFC05;

    /// @notice cbETH remediation: amounts withdrawn from reserves (8 dec for LBTC, 18 for rETH/weETH)
    uint256 public constant LBTC_WITHDRAW_AMOUNT = 0.23e8;
    uint256 public constant RETH_WITHDRAW_AMOUNT = 4e18;
    uint256 public constant WEETH_WITHDRAW_AMOUNT = 7e18;

    /// @notice expected total reserve decrease per market, used in validate()
    uint256 public constant CBXRP_RESERVES_DOWN = 10839e6;
    uint256 public constant WETH_RESERVES_DOWN = 6.22e18;
    uint256 public constant USDC_RESERVES_DOWN = 8216.397e6;
    uint256 public constant AERO_RESERVES_DOWN = 9744e18;
    uint256 public constant LBTC_RESERVES_DOWN = 0.23e8;
    uint256 public constant RETH_RESERVES_DOWN = 4e18;
    uint256 public constant WEETH_RESERVES_DOWN = 7e18;

    /// @notice minimum live cash required per market, in basis points of the
    ///         total amount its _reduceReserves actions pull (1.1x buffer)
    uint256 public constant CASH_HEADROOM_BPS = 11_000;

    mapping(address market => uint256 reserves) internal reservesBefore;
    mapping(bytes32 pair => uint256 borrowBalance) internal borrowBefore;
    uint256 internal foundationLbtcBefore;
    uint256 internal foundationRethBefore;
    uint256 internal foundationWeethBefore;

    function name() external pure override returns (string memory) {
        return "MIP-X61";
    }

    function _repayments() internal pure returns (Repayment[] memory r) {
        r = new Repayment[](4);
        r[0] = Repayment(
            "MOONWELL_cbXRP",
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            10839e6,
            "10,839 cbXRP"
        );
        r[1] = Repayment(
            "MOONWELL_WETH",
            0x42d3617495205563f85f85671cD8F9BcC9bca7E4,
            6.22e18,
            "6.22 WETH"
        );
        r[2] = Repayment(
            "MOONWELL_USDC",
            0xF61D6742Eea5E1f29cb4B96Cf7108F32424d562c,
            8216.397e6,
            "8,216.397 USDC"
        );
        r[3] = Repayment(
            "MOONWELL_AERO",
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            9744e18,
            "9,744 AERO"
        );
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            _pushBadDebtRepay(addresses, repayments[i]);
        }

        // cbETH remediation: withdraw reserves and send to FOUNDATION_MULTISIG
        _pushReserveWithdrawal(
            addresses,
            "MOONWELL_LBTC",
            LBTC_WITHDRAW_AMOUNT,
            "0.23 LBTC"
        );
        _pushReserveWithdrawal(
            addresses,
            "MOONWELL_rETH",
            RETH_WITHDRAW_AMOUNT,
            "4 rETH"
        );
        _pushReserveWithdrawal(
            addresses,
            "MOONWELL_weETH",
            WEETH_WITHDRAW_AMOUNT,
            "7 weETH"
        );

        // Ethereum: transfer supply/borrow cap guardian to Anthias multisig
        address unitroller = addresses.getAddress(
            "UNITROLLER",
            ETHEREUM_CHAIN_ID
        );

        _pushAction(
            unitroller,
            abi.encodeWithSignature(
                "_setBorrowCapGuardian(address)",
                NEW_CAP_GUARDIAN
            ),
            "Set borrow cap guardian to Anthias multisig on Ethereum",
            ActionType.Ethereum
        );

        _pushAction(
            unitroller,
            abi.encodeWithSignature(
                "_setSupplyCapGuardian(address)",
                NEW_CAP_GUARDIAN
            ),
            "Set supply cap guardian to Anthias multisig on Ethereum",
            ActionType.Ethereum
        );
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(repayments[i].market));

            uint256 borrowBalance = market.borrowBalanceStored(
                repayments[i].borrower
            );

            assertGe(
                borrowBalance,
                repayments[i].amount,
                string.concat(
                    "borrow balance below repay amount for ",
                    vm.toString(repayments[i].borrower),
                    " on ",
                    repayments[i].market
                )
            );

            reservesBefore[address(market)] = market.totalReserves();
            borrowBefore[
                keccak256(
                    abi.encodePacked(address(market), repayments[i].borrower)
                )
            ] = borrowBalance;
        }

        // snapshot reserves for cbETH remediation markets
        reservesBefore[addresses.getAddress("MOONWELL_LBTC")] = MErc20(
            addresses.getAddress("MOONWELL_LBTC")
        ).totalReserves();
        reservesBefore[addresses.getAddress("MOONWELL_rETH")] = MErc20(
            addresses.getAddress("MOONWELL_rETH")
        ).totalReserves();
        reservesBefore[addresses.getAddress("MOONWELL_weETH")] = MErc20(
            addresses.getAddress("MOONWELL_weETH")
        ).totalReserves();

        // snapshot FOUNDATION_MULTISIG balances before simulation
        address foundation = addresses.getAddress("FOUNDATION_MULTISIG");
        foundationLbtcBefore = IERC20(
            MErc20(addresses.getAddress("MOONWELL_LBTC")).underlying()
        ).balanceOf(foundation);
        foundationRethBefore = IERC20(
            MErc20(addresses.getAddress("MOONWELL_rETH")).underlying()
        ).balanceOf(foundation);
        foundationWeethBefore = IERC20(
            MErc20(addresses.getAddress("MOONWELL_weETH")).underlying()
        ).balanceOf(foundation);

        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_cbXRP",
            CBXRP_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_WETH",
            WETH_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_USDC",
            USDC_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_AERO",
            AERO_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_LBTC",
            LBTC_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_rETH",
            RETH_RESERVES_DOWN
        );
        _assertExecutionHeadroom(
            addresses,
            "MOONWELL_weETH",
            WEETH_RESERVES_DOWN
        );
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);

        Repayment[] memory repayments = _repayments();
        for (uint256 i = 0; i < repayments.length; i++) {
            _assertRepayEffects(addresses, repayments[i]);
        }

        _assertReservesDown(addresses, "MOONWELL_cbXRP", CBXRP_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_WETH", WETH_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_USDC", USDC_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_AERO", AERO_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_LBTC", LBTC_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_rETH", RETH_RESERVES_DOWN);
        _assertReservesDown(addresses, "MOONWELL_weETH", WEETH_RESERVES_DOWN);

        // cbETH remediation transfers are exact
        address foundation = addresses.getAddress("FOUNDATION_MULTISIG");

        assertEq(
            IERC20(MErc20(addresses.getAddress("MOONWELL_LBTC")).underlying())
                .balanceOf(foundation) - foundationLbtcBefore,
            LBTC_WITHDRAW_AMOUNT,
            "FOUNDATION_MULTISIG did not receive 0.23 LBTC"
        );
        assertEq(
            IERC20(MErc20(addresses.getAddress("MOONWELL_rETH")).underlying())
                .balanceOf(foundation) - foundationRethBefore,
            RETH_WITHDRAW_AMOUNT,
            "FOUNDATION_MULTISIG did not receive 4 rETH"
        );
        assertEq(
            IERC20(MErc20(addresses.getAddress("MOONWELL_weETH")).underlying())
                .balanceOf(foundation) - foundationWeethBefore,
            WEETH_WITHDRAW_AMOUNT,
            "FOUNDATION_MULTISIG did not receive 7 weETH"
        );

        // Ethereum: verify cap guardians were updated
        vm.selectFork(ETHEREUM_FORK_ID);
        address unitroller = addresses.getAddress(
            "UNITROLLER",
            ETHEREUM_CHAIN_ID
        );

        assertEq(
            IComptrollerCaps(unitroller).borrowCapGuardian(),
            NEW_CAP_GUARDIAN,
            "borrowCapGuardian not updated on Ethereum"
        );
        assertEq(
            IComptrollerCaps(unitroller).supplyCapGuardian(),
            NEW_CAP_GUARDIAN,
            "supplyCapGuardian not updated on Ethereum"
        );
    }

    function _pushBadDebtRepay(
        Addresses addresses,
        Repayment memory rec
    ) internal {
        address market = addresses.getAddress(rec.market);
        address underlying = MErc20(market).underlying();

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

    function _pushReserveWithdrawal(
        Addresses addresses,
        string memory marketName,
        uint256 amount,
        string memory label
    ) internal {
        address market = addresses.getAddress(marketName);
        address underlying = MErc20(market).underlying();
        address foundation = addresses.getAddress("FOUNDATION_MULTISIG");

        _pushAction(
            market,
            abi.encodeWithSignature("_reduceReserves(uint256)", amount),
            string.concat(
                "Reduce ",
                label,
                " reserves from ",
                marketName,
                " for cbETH remediation"
            ),
            ActionType.Base
        );

        _pushAction(
            underlying,
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                foundation,
                amount
            ),
            string.concat(
                "Transfer ",
                label,
                " to FOUNDATION_MULTISIG for cbETH remediation swap"
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

        uint256 borrowDecrease = borrowBalanceBefore - borrowBalanceAfter;
        assertLe(
            borrowDecrease,
            rec.amount,
            string.concat(
                "borrow decrease exceeds repaid amount for ",
                vm.toString(rec.borrower),
                " on ",
                rec.market
            )
        );
        assertGe(
            borrowDecrease,
            (rec.amount * 80) / 100,
            string.concat(
                "borrow decrease far below repaid amount for ",
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

        uint256 reservesDecrease = before - market.totalReserves();
        assertLe(
            reservesDecrease,
            expected,
            string.concat("reserves decrease exceeds target on ", marketName)
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-X63: Anthias Labs Monthly Risk Parameters + Reserve
///        Recommendations August 2026
/// @notice In addition to the market updates configured in x63.json (wrsETH
///         collateral factor on Base and Optimism), this proposal executes the
///         August 2026 reserve recommendations: repay bad debt on behalf of
///         insolvent accounts (supplying < $1 of collateral), funded from
///         same-market protocol reserves
///         (reduce reserves -> approve -> repayBorrowBehalf, following
///         MIP-X61 / MIP-X60).
///
///         Per market: one _reduceReserves for the total, one approve for the
///         total, then one repayBorrowBehalf per borrower. WETH reserves are
///         reduced through MWETH_OWNER_WRAPPER, which wraps the received ETH
///         and HOLDS it; the separate withdrawToken action then moves the
///         WETH to the Temporal Governor — do not drop that action.
///
///         The cbETH rows from the forum plan are EXCLUDED: the Base cbETH
///         market currently holds ~0 cash (fully utilized), so
///         _reduceReserves cannot execute and would make the whole proposal
///         unexecutable (precedent: MIP-M45 excluded the GLMR native market).
contract mipx63 is MarketUpdateV2Template {
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
        return "MIP-X63";
    }

    function _basePlans() internal pure returns (Plan[] memory p) {
        p = new Plan[](12);

        p[0].market = "MOONWELL_AERO";
        p[0].totalReduce = 6314.3566e18;
        p[0].repays = new Repayment[](1);
        p[0].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            6314.3566e18,
            "6,314.3566 AERO"
        );

        p[1].market = "MOONWELL_cbBTC";
        p[1].totalReduce = 0.03990043e8;
        p[1].repays = new Repayment[](3);
        p[1].repays[0] = Repayment(
            0x2a2621a41011a22B5ADdA2593F4F81151C2AA4c7,
            0.01460137e8,
            "0.01460137 cbBTC"
        );
        p[1].repays[1] = Repayment(
            0x45854310c3302c5dAb9C0c745E8058d485a4ae8A,
            0.00975022e8,
            "0.00975022 cbBTC"
        );
        p[1].repays[2] = Repayment(
            0xA36C71930F378875F09D6358073324Ed015F2762,
            0.01554884e8,
            "0.01554884 cbBTC"
        );

        p[2].market = "MOONWELL_cbXRP";
        p[2].totalReduce = 2910.2308e6;
        p[2].repays = new Repayment[](1);
        p[2].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            2910.2308e6,
            "2,910.2308 cbXRP"
        );

        p[3].market = "MOONWELL_DAI";
        p[3].totalReduce = 1550.7035003e18;
        p[3].repays = new Repayment[](1);
        p[3].repays[0] = Repayment(
            0x0441455e280D3a47e8Ab2b4C82f68274dFC8D8A7,
            1550.7035003e18,
            "1,550.7035003 DAI"
        );

        p[4].market = "MOONWELL_EURC";
        p[4].totalReduce = 747.0118e6;
        p[4].repays = new Repayment[](1);
        p[4].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            747.0118e6,
            "747.0118 EURC"
        );

        p[5].market = "MOONWELL_MORPHO";
        p[5].totalReduce = 112.9525e18;
        p[5].repays = new Repayment[](1);
        p[5].repays[0] = Repayment(
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            112.9525e18,
            "112.9525 MORPHO"
        );

        p[6].market = "MOONWELL_TBTC";
        p[6].totalReduce = 0.01212566e18;
        p[6].repays = new Repayment[](1);
        p[6].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            0.01212566e18,
            "0.01212566 tBTC"
        );

        p[7].market = "MOONWELL_USDC";
        p[7].totalReduce = 11807.44739e6;
        p[7].repays = new Repayment[](22);
        p[7].repays[0] = Repayment(
            0x030B277dbfFD53ebBaFFcA6aDD3865c6CBd028A0,
            662.242661e6,
            "662.242661 USDC"
        );
        p[7].repays[1] = Repayment(
            0x0cCb58BDbE1113AfA9D13757558b98856D485F21,
            149.499694e6,
            "149.499694 USDC"
        );
        p[7].repays[2] = Repayment(
            0x185542374ce5Fc8bF8F215F5Fc681370704fD124,
            2260.789977e6,
            "2,260.789977 USDC"
        );
        p[7].repays[3] = Repayment(
            0x22732C901C0C46128b418AE30b7b53FB95D18B38,
            234.224819e6,
            "234.224819 USDC"
        );
        p[7].repays[4] = Repayment(
            0x2Ac5E20ed9773a751d972DEb832c8F7f490Bd752,
            145.454499e6,
            "145.454499 USDC"
        );
        p[7].repays[5] = Repayment(
            0x2ad6EdEa3EcD174Be69E47BDC37ffFE5AdAc6807,
            216.839002e6,
            "216.839002 USDC"
        );
        p[7].repays[6] = Repayment(
            0x3e2178CF851A0e5cbF84c0ff53f820ad7EAD703b,
            912.154603e6,
            "912.154603 USDC"
        );
        p[7].repays[7] = Repayment(
            0x45854310c3302c5dAb9C0c745E8058d485a4ae8A,
            136.067406e6,
            "136.067406 USDC"
        );
        p[7].repays[8] = Repayment(
            0x45b4F0B3216038632Da1aEbBbf52202F1D315307,
            587.799643e6,
            "587.799643 USDC"
        );
        p[7].repays[9] = Repayment(
            0x76e5db63BF8F1F22886EBe88fB4ed6859b36B6cD,
            884.176559e6,
            "884.176559 USDC"
        );
        p[7].repays[10] = Repayment(
            0x88E57C01BeBA95b51006dF6dE835FDec38D370af,
            159.774541e6,
            "159.774541 USDC"
        );
        p[7].repays[11] = Repayment(
            0x8c40a7D8C37B30C8A4B228CA0885E65444A676a0,
            812.523101e6,
            "812.523101 USDC"
        );
        p[7].repays[12] = Repayment(
            0x91E66db5904fbac6c877e8696BB4ED50841AE442,
            119.186237e6,
            "119.186237 USDC"
        );
        p[7].repays[13] = Repayment(
            0x9CDE2b9D159036D49a9cb98D0560eFc928c139D0,
            409.147974e6,
            "409.147974 USDC"
        );
        p[7].repays[14] = Repayment(
            0xa4CaA152822A67Bd8c8a689afC317b7b780F8210,
            112.900876e6,
            "112.900876 USDC"
        );
        p[7].repays[15] = Repayment(
            0xAb2a43335A25566cD4Cb446Ea03b873aA26D0528,
            200.673394e6,
            "200.673394 USDC"
        );
        p[7].repays[16] = Repayment(
            0xb506428de44980901fd2EDa619d23342FB8F2ed4,
            363.07585e6,
            "363.075850 USDC"
        );
        p[7].repays[17] = Repayment(
            0xc362B9936F973fC7D8729180a11cEFCaF1fe8e40,
            181.807736e6,
            "181.807736 USDC"
        );
        p[7].repays[18] = Repayment(
            0xDdF093745B0a723c68a8f040AB03e72eee2B8F60,
            326.17474e6,
            "326.174740 USDC"
        );
        p[7].repays[19] = Repayment(
            0xE54724b107bb90dD24260CEf0C52b4106f57B2A2,
            133.012572e6,
            "133.012572 USDC"
        );
        p[7].repays[20] = Repayment(
            0xe811980cD6A377796c4cC35f6D3A2362cbEFe697,
            804.212711e6,
            "804.212711 USDC"
        );
        p[7].repays[21] = Repayment(
            0xF61D6742Eea5E1f29cb4B96Cf7108F32424d562c,
            1995.708795e6,
            "1,995.708795 USDC"
        );

        p[8].market = "MOONWELL_USDS";
        p[8].totalReduce = 189.9855e18;
        p[8].repays = new Repayment[](1);
        p[8].repays[0] = Repayment(
            0xCe7b587609586Df23fD704eDf067D3616D62514B,
            189.9855e18,
            "189.9855 USDS"
        );

        p[9].market = "MOONWELL_VIRTUAL";
        p[9].totalReduce = 18964.3568e18;
        p[9].repays = new Repayment[](1);
        p[9].repays[0] = Repayment(
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            18964.3568e18,
            "18,964.3568 VIRTUAL"
        );

        p[10].market = "MOONWELL_WETH";
        p[10].totalReduce = 1.5952e18;
        p[10].repays = new Repayment[](4);
        p[10].repays[0] = Repayment(
            0x3B87f7D473550ef9e53e46Baae856608f8b8A0C4,
            0.34091611e18,
            "0.34091611 WETH"
        );
        p[10].repays[1] = Repayment(
            0x42d3617495205563f85f85671cD8F9BcC9bca7E4,
            0.75892153e18,
            "0.75892153 WETH"
        );
        p[10].repays[2] = Repayment(
            0xEe3a8FAeF6C61C97E4039B3f569276605E61c5C3,
            0.3183427e18,
            "0.3183427 WETH"
        );
        p[10].repays[3] = Repayment(
            0xf0f2f08A6327c0A824E71eE1897634184cE1225C,
            0.17701966e18,
            "0.17701966 WETH"
        );

        p[11].market = "MOONWELL_wstETH";
        p[11].totalReduce = 0.6678e18;
        p[11].repays = new Repayment[](1);
        p[11].repays[0] = Repayment(
            0x42Ecd332D47C91CbC83B39bD7f53CEbe5E9734bB,
            0.6678e18,
            "0.6678 wstETH"
        );
    }

    function _optimismPlans() internal pure returns (Plan[] memory p) {
        p = new Plan[](2);

        p[0].market = "MOONWELL_rETH";
        p[0].totalReduce = 0.2806e18;
        p[0].repays = new Repayment[](1);
        p[0].repays[0] = Repayment(
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            0.2806e18,
            "0.2806 rETH"
        );

        p[1].market = "MOONWELL_wstETH";
        p[1].totalReduce = 1.3979252e18;
        p[1].repays = new Repayment[](1);
        p[1].repays[0] = Repayment(
            0xA98E339f5a0F135792286d481B4e23d91A667d3f,
            1.3979252e18,
            "1.3979252 wstETH"
        );
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        vm.selectFork(BASE_FORK_ID);
        Plan[] memory basePlans = _basePlans();
        for (uint256 i = 0; i < basePlans.length; i++) {
            _pushPlan(addresses, basePlans[i], ActionType.Base, "Base");
        }

        vm.selectFork(OPTIMISM_FORK_ID);
        Plan[] memory opPlans = _optimismPlans();
        for (uint256 i = 0; i < opPlans.length; i++) {
            _pushPlan(addresses, opPlans[i], ActionType.Optimism, "Optimism");
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        super.beforeSimulationHook(addresses);

        vm.selectFork(BASE_FORK_ID);
        _snapshotPlans(addresses, _basePlans());

        vm.selectFork(OPTIMISM_FORK_ID);
        _snapshotPlans(addresses, _optimismPlans());
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        vm.selectFork(BASE_FORK_ID);
        _validatePlans(addresses, _basePlans());

        vm.selectFork(OPTIMISM_FORK_ID);
        _validatePlans(addresses, _optimismPlans());
    }

    /// @notice push reduce -> (withdraw) -> approve -> repay actions for one
    ///         market's repayment plan. Assumes the plan's chain fork is
    ///         selected so underlying() reads resolve.
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

        bool isBaseWeth = actionType == ActionType.Base &&
            keccak256(abi.encodePacked(plan.market)) ==
            keccak256(abi.encodePacked("MOONWELL_WETH"));

        address reduceTarget = isBaseWeth
            ? addresses.getAddress("MWETH_OWNER_WRAPPER")
            : market;

        _pushAction(
            reduceTarget,
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

        if (isBaseWeth) {
            _pushAction(
                reduceTarget,
                abi.encodeWithSignature(
                    "withdrawToken(address,address,uint256)",
                    underlying,
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    plan.totalReduce
                ),
                "Withdraw WETH from MWETH_OWNER_WRAPPER to the Temporal Governor",
                actionType
            );
        }

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

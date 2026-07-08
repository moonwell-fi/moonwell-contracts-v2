//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title MIP-M45: Moonbeam Sunset — Withdraw Reserves and Pause Markets
/// @notice Executes two initiatives on Moonbeam as part of the Moonbeam
///         Sunset:
///         1. Withdraw the safe portion of protocol reserves
///            (reserves - total borrows, rounded down for ETH.wh and BTC.wh)
///            from seven markets and transfer the underlying tokens to the
///            Foundation-designated wallet.
///         2. Pause minting and borrowing on every live Moonbeam market.
///         The GLMR market has negative reserves-minus-borrows and is only
///         paused, not withdrawn from.
contract mipm45 is HybridProposalV2 {
    struct Withdrawal {
        string market;
        uint256 amount;
        string label;
    }

    /// @notice wallet receiving the withdrawn reserves
    address public constant RECIPIENT =
        0x9917Ea34179D87F06C8b9D4AfB8BD78248B434ef;

    /// @notice minimum live cash required per market, in basis points of the
    ///         amount its _reduceReserves action pulls (1.1x buffer)
    uint256 public constant CASH_HEADROOM_BPS = 11_000;

    mapping(address market => uint256 reserves) internal reservesBefore;
    mapping(address market => uint256 balance) internal recipientBalanceBefore;

    function name() external pure override returns (string memory) {
        return "MIP-M45";
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-m45/MIP-M45.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    /// @notice safe-to-withdraw amounts = reserves - total borrows, rounded
    ///         to 2 decimal places (ETH.wh and BTC.wh rounded down an extra
    ///         0.01 to stay under the live on-chain margin). xcDOT is capped
    ///         by the market's physical token balance instead: getCash()
    ///         reports ~550k DOT but includes ~513k of badDebt() from the
    ///         fixer delegate — only ~35,942 xcDOT are actually held and the
    ///         balance is trending down as suppliers exit, so the withdrawal
    ///         is sized to 30,000 (1.2x cash buffer at sizing time; re-verify
    ///         xcDOT.balanceOf(mxcDOT) right before proposing).
    function _withdrawals() internal pure returns (Withdrawal[] memory w) {
        w = new Withdrawal[](7);
        w[0] = Withdrawal("mxcUSDT", 22227.75e6, "22,227.75 xcUSDT");
        w[1] = Withdrawal("mxcUSDC", 15795.89e6, "15,795.89 xcUSDC");
        w[2] = Withdrawal("mxcDOT", 30000e10, "30,000 xcDOT");
        w[3] = Withdrawal("mUSDCwh", 54800.43e6, "54,800.43 USDC.wh");
        w[4] = Withdrawal("mFRAX", 473.41e18, "473.41 FRAX");
        w[5] = Withdrawal("mETHwh", 8.58e18, "8.58 ETH.wh");
        w[6] = Withdrawal("MOONWELL_mWBTC", 0.37e8, "0.37 WBTC.wh");
    }

    /// @notice every live Moonbeam market gets mint and borrow paused
    function _pausedMarkets() internal pure returns (string[] memory m) {
        m = new string[](8);
        m[0] = "mGLIMMER";
        m[1] = "mxcDOT";
        m[2] = "mxcUSDT";
        m[3] = "mxcUSDC";
        m[4] = "mUSDCwh";
        m[5] = "mFRAX";
        m[6] = "mETHwh";
        m[7] = "MOONWELL_mWBTC";
    }

    function build(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        Withdrawal[] memory withdrawals = _withdrawals();
        for (uint256 i = 0; i < withdrawals.length; i++) {
            address market = addresses.getAddress(withdrawals[i].market);
            address underlying = MErc20(market).underlying();

            _pushAction(
                market,
                abi.encodeWithSignature(
                    "_reduceReserves(uint256)",
                    withdrawals[i].amount
                ),
                string.concat(
                    "Reduce reserves of ",
                    withdrawals[i].label,
                    " from ",
                    withdrawals[i].market,
                    " on Moonbeam"
                ),
                ActionType.Moonbeam
            );

            _pushAction(
                underlying,
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    RECIPIENT,
                    withdrawals[i].amount
                ),
                string.concat(
                    "Transfer ",
                    withdrawals[i].label,
                    " to the Foundation-designated wallet"
                ),
                ActionType.Moonbeam
            );
        }

        address unitroller = addresses.getAddress("UNITROLLER");
        string[] memory pausedMarkets = _pausedMarkets();
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            address market = addresses.getAddress(pausedMarkets[i]);

            _pushAction(
                unitroller,
                abi.encodeWithSignature(
                    "_setMintPaused(address,bool)",
                    market,
                    true
                ),
                string.concat("Pause minting on ", pausedMarkets[i]),
                ActionType.Moonbeam
            );

            _pushAction(
                unitroller,
                abi.encodeWithSignature(
                    "_setBorrowPaused(address,bool)",
                    market,
                    true
                ),
                string.concat("Pause borrowing on ", pausedMarkets[i]),
                ActionType.Moonbeam
            );
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        Withdrawal[] memory withdrawals = _withdrawals();
        for (uint256 i = 0; i < withdrawals.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(withdrawals[i].market));
            IERC20 underlying = IERC20(market.underlying());

            assertGe(
                market.totalReserves(),
                withdrawals[i].amount,
                string.concat(
                    "insufficient reserves to execute _reduceReserves on ",
                    withdrawals[i].market
                )
            );

            // use the physical token balance, not getCash(): on bad-debt
            // fixer delegates (mxcDOT, mFRAX) getCash() is inflated by
            // badDebt() and overstates what _reduceReserves can transfer out
            assertGe(
                underlying.balanceOf(address(market)),
                (withdrawals[i].amount * CASH_HEADROOM_BPS) / 10_000,
                string.concat(
                    "cash headroom below 1.1x on ",
                    withdrawals[i].market
                )
            );

            reservesBefore[address(market)] = market.totalReserves();
            recipientBalanceBefore[address(market)] = underlying.balanceOf(
                RECIPIENT
            );
        }
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        Withdrawal[] memory withdrawals = _withdrawals();
        for (uint256 i = 0; i < withdrawals.length; i++) {
            MErc20 market = MErc20(addresses.getAddress(withdrawals[i].market));
            IERC20 underlying = IERC20(market.underlying());

            assertLt(
                market.totalReserves(),
                reservesBefore[address(market)],
                string.concat(
                    "totalReserves did not decrease on ",
                    withdrawals[i].market
                )
            );

            uint256 reservesDecrease = reservesBefore[address(market)] -
                market.totalReserves();
            assertLe(
                reservesDecrease,
                withdrawals[i].amount,
                string.concat(
                    "reserves decrease exceeds target on ",
                    withdrawals[i].market
                )
            );

            assertEq(
                underlying.balanceOf(RECIPIENT) -
                    recipientBalanceBefore[address(market)],
                withdrawals[i].amount,
                string.concat(
                    "RECIPIENT did not receive ",
                    withdrawals[i].label
                )
            );
        }

        Comptroller comptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        string[] memory pausedMarkets = _pausedMarkets();
        for (uint256 i = 0; i < pausedMarkets.length; i++) {
            address market = addresses.getAddress(pausedMarkets[i]);

            assertTrue(
                comptroller.mintGuardianPaused(market),
                string.concat("mint not paused on ", pausedMarkets[i])
            );
            assertTrue(
                comptroller.borrowGuardianPaused(market),
                string.concat("borrow not paused on ", pausedMarkets[i])
            );
        }
    }
}

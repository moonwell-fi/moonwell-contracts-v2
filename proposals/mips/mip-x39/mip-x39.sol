//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X39: rETH Market Exchange Rate Feed and Debt Management
/// @author Moonwell Contributors
/// @notice Proposal to:
///         1. Update rETH oracle on Base to use exchange-rate feed instead of market price
///         2. Update rETH oracle on Optimism to use exchange-rate feed instead of market price
///         3. Withdraw WETH reserves on Optimism and transfer to BAD_DEBT_REPAYER_EOA
///            for repaying bad debt on rETH and cbETH markets
contract mipx39 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X39";

    // Debt management constants
    uint256 public constant WETH_AMOUNT = 2.6 ether;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x39/x39.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        (, address deployerAddress, ) = vm.readCallers();

        if (DO_DEPLOY) deploy(addresses, deployerAddress);
        if (DO_AFTER_DEPLOY) afterDeploy(addresses, deployerAddress);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, deployerAddress);
        if (DO_TEARDOWN) teardown(addresses, deployerAddress);
        if (DO_VALIDATE) {
            validate(addresses, deployerAddress);
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            printProposalActionSteps();

            addresses.removeAllRestrictions();
            printCalldata(addresses);

            _printAddressesChanges(addresses);
        }
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        // Deploy new ChainlinkCompositeOracle for rETH on Base
        vm.selectFork(BASE_FORK_ID);

        if (
            !addresses.isAddressSet("CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE")
        ) {
            vm.startBroadcast();

            address baseEthUsdFeed = addresses.getAddress("CHAINLINK_ETH_USD");
            address baseRethEthExchangeRateFeed = addresses.getAddress(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE"
            );

            address baseRethOracle = address(
                new ChainlinkCompositeOracle(
                    baseEthUsdFeed,
                    baseRethEthExchangeRateFeed,
                    address(0)
                )
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
                baseRethOracle
            );
        }

        // Deploy new ChainlinkCompositeOracle for rETH on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);

        if (
            !addresses.isAddressSet(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
                block.chainid
            )
        ) {
            vm.startBroadcast();

            address optimismEthUsdFeed = addresses.getAddress(
                "CHAINLINK_ETH_USD"
            );
            address optimismRethEthExchangeRateFeed = addresses.getAddress(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE"
            );

            address optimismRethOracle = address(
                new ChainlinkCompositeOracle(
                    optimismEthUsdFeed,
                    optimismRethEthExchangeRateFeed,
                    address(0)
                )
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
                optimismRethOracle
            );
        }
    }

    function build(Addresses addresses) public override {
        // ============ BASE CHAIN ACTIONS ============
        vm.selectFork(BASE_FORK_ID);

        // Update rETH oracle price feed on Base
        address baseChainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        address baseRethOracle = addresses.getAddress(
            "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE"
        );
        _pushAction(
            baseChainlinkOracle,
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "rETH",
                baseRethOracle
            ),
            "Update rETH oracle to exchange rate feed on Base",
            ActionType.Base
        );

        // ============ OPTIMISM CHAIN ACTIONS ============
        vm.selectFork(OPTIMISM_FORK_ID);

        // Update rETH oracle price feed on Optimism
        address optimismChainlinkOracle = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );
        address optimismRethOracle = addresses.getAddress(
            "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
            block.chainid
        );
        _pushAction(
            optimismChainlinkOracle,
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "rETH",
                optimismRethOracle
            ),
            "Update rETH oracle to exchange rate feed on Optimism",
            ActionType.Optimism
        );

        address moonwellWeth = addresses.getAddress("MOONWELL_WETH");

        // Reduce WETH reserves - ETH will be sent to TEMPORAL_GOVERNOR via WETH_UNWRAPPER
        _pushAction(
            moonwellWeth,
            abi.encodeWithSignature("_reduceReserves(uint256)", WETH_AMOUNT),
            "Reduce 2.6 WETH reserves from MOONWELL_WETH on Optimism (sends ETH to TEMPORAL_GOVERNOR)",
            ActionType.Optimism
        );

        // Transfer ETH from TEMPORAL_GOVERNOR to BAD_DEBT_REPAYER_EOA
        address badDebtRepayerEoa = addresses.getAddress(
            "BAD_DEBT_REPAYER_EOA"
        );
        _pushAction(
            badDebtRepayerEoa,
            WETH_AMOUNT,
            "",
            "Transfer 2.6 ETH to BAD_DEBT_REPAYER_EOA for bad debt repayment",
            ActionType.Optimism
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        // ============ VALIDATE BASE CHAIN ============
        vm.selectFork(BASE_FORK_ID);

        // Validate oracle is updated
        ChainlinkOracle baseChainlinkOracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        AggregatorV3Interface baseFeed = baseChainlinkOracle.getFeed("rETH");
        address baseRethOracle = addresses.getAddress(
            "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE"
        );
        assertEq(
            address(baseFeed),
            baseRethOracle,
            "Base rETH oracle not updated"
        );

        // Validate price can be fetched
        (, int256 basePrice, , , ) = baseFeed.latestRoundData();
        assertGt(uint256(basePrice), 0, "Base rETH price check failed");

        // ============ VALIDATE OPTIMISM CHAIN ============
        vm.selectFork(OPTIMISM_FORK_ID);

        // Validate oracle is updated on Optimism
        ChainlinkOracle optimismChainlinkOracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        AggregatorV3Interface optimismFeed = optimismChainlinkOracle.getFeed(
            "rETH"
        );

        address optimismRethOracle = addresses.getAddress(
            "CHAINLINK_RETH_ETH_EXCHANGE_RATE_ORACLE",
            block.chainid
        );

        assertEq(
            address(optimismFeed),
            optimismRethOracle,
            "Optimism rETH oracle not updated"
        );

        // Validate price can be fetched on Optimism
        (, int256 optimismPrice, , , ) = optimismFeed.latestRoundData();
        assertGt(uint256(optimismPrice), 0, "Optimism rETH price check failed");

        address badDebtRepayerEoa = addresses.getAddress(
            "BAD_DEBT_REPAYER_EOA"
        );

        // Validate BAD_DEBT_REPAYER_EOA received ETH
        uint256 ethBalance = badDebtRepayerEoa.balance;
        assertGe(
            ethBalance,
            WETH_AMOUNT,
            "BAD_DEBT_REPAYER_EOA should have received ETH on Optimism"
        );
    }
}

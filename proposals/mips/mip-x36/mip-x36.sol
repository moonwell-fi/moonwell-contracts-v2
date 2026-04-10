//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ChainlinkOracle} from "@protocol/oracles/ChainlinkOracle.sol";
import {ChainlinkCompositeOracle} from "@protocol/oracles/ChainlinkCompositeOracle.sol";
import {AggregatorV3Interface} from "@protocol/oracles/AggregatorV3Interface.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X36: Disable Mint/Borrow in wrsETH Markets and Transition to Exchange-Rate Oracle
/// @author Moonwell Contributors
/// @notice Proposal to disable new positions in wrsETH markets on Base and Optimism by:
///         1. Pausing minting operations for wrsETH markets
///         2. Pausing borrowing operations for wrsETH markets
///         3. Deploying new ChainlinkCompositeOracle contracts using exchange rate feeds
///         4. Updating oracle addresses for wrsETH markets to use exchange rate feeds
contract mipx36 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X36";

    // Storage for deployed oracles
    ChainlinkCompositeOracle public baseWrsethOracle;
    ChainlinkCompositeOracle public optimismWrsethOracle;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x36/x36.md")
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
        // Deploy new ChainlinkCompositeOracle for Base wrsETH
        vm.selectFork(BASE_FORK_ID);

        if (!addresses.isAddressSet("CHAINLINK_wrsETH_COMPOSITE_ORACLE")) {
            vm.startBroadcast();

            address baseEthUsdFeed = addresses.getAddress("CHAINLINK_ETH_USD");
            address baseWrsethEthExchangeRateFeed = addresses.getAddress(
                "CHAINLINK_wrsETH_ETH_EXCHANGE_RATE"
            );

            baseWrsethOracle = new ChainlinkCompositeOracle(
                baseEthUsdFeed,
                baseWrsethEthExchangeRateFeed,
                address(0)
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "CHAINLINK_wrsETH_COMPOSITE_ORACLE",
                address(baseWrsethOracle)
            );
        } else {
            baseWrsethOracle = ChainlinkCompositeOracle(
                addresses.getAddress("CHAINLINK_wrsETH_COMPOSITE_ORACLE")
            );
        }

        // Deploy new ChainlinkCompositeOracle for Optimism wrsETH
        vm.selectFork(OPTIMISM_FORK_ID);

        if (!addresses.isAddressSet("CHAINLINK_wrsETH_COMPOSITE_ORACLE")) {
            vm.startBroadcast();

            address optimismEthUsdFeed = addresses.getAddress(
                "CHAINLINK_ETH_USD"
            );
            address optimismWrsethEthExchangeRateFeed = addresses.getAddress(
                "CHAINLINK_wrsETH_ETH_EXCHANGE_RATE"
            );

            optimismWrsethOracle = new ChainlinkCompositeOracle(
                optimismEthUsdFeed,
                optimismWrsethEthExchangeRateFeed,
                address(0)
            );

            vm.stopBroadcast();

            addresses.addAddress(
                "CHAINLINK_wrsETH_COMPOSITE_ORACLE",
                address(optimismWrsethOracle)
            );
        } else {
            optimismWrsethOracle = ChainlinkCompositeOracle(
                addresses.getAddress("CHAINLINK_wrsETH_COMPOSITE_ORACLE")
            );
        }
    }

    function build(Addresses addresses) public override {
        // ============ BASE CHAIN ACTIONS ============
        vm.selectFork(BASE_FORK_ID);

        address baseComptroller = addresses.getAddress("UNITROLLER");
        address baseWrsethMToken = addresses.getAddress("MOONWELL_wrsETH");

        // Pause minting on Base
        _pushAction(
            baseComptroller,
            abi.encodeWithSignature(
                "_setMintPaused(address,bool)",
                baseWrsethMToken,
                true
            ),
            "Pause minting for wrsETH on Base",
            ActionType.Base
        );

        // Pause borrowing on Base
        _pushAction(
            baseComptroller,
            abi.encodeWithSignature(
                "_setBorrowPaused(address,bool)",
                baseWrsethMToken,
                true
            ),
            "Pause borrowing for wrsETH on Base",
            ActionType.Base
        );

        // Update oracle price feed on Base
        // Use addresses file instead of storage variable for consistent calldata generation
        address baseChainlinkOracle = addresses.getAddress("CHAINLINK_ORACLE");
        address baseWrsethOracleAddr = addresses.getAddress(
            "CHAINLINK_wrsETH_COMPOSITE_ORACLE"
        );
        _pushAction(
            baseChainlinkOracle,
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "wrsETH",
                baseWrsethOracleAddr
            ),
            "Update wrsETH oracle to exchange rate feed on Base",
            ActionType.Base
        );

        // ============ OPTIMISM CHAIN ACTIONS ============
        vm.selectFork(OPTIMISM_FORK_ID);

        address optimismComptroller = addresses.getAddress("UNITROLLER");
        address optimismWrsethMToken = addresses.getAddress("MOONWELL_wrsETH");

        // Pause minting on Optimism
        _pushAction(
            optimismComptroller,
            abi.encodeWithSignature(
                "_setMintPaused(address,bool)",
                optimismWrsethMToken,
                true
            ),
            "Pause minting for wrsETH on Optimism",
            ActionType.Optimism
        );

        // Pause borrowing on Optimism
        _pushAction(
            optimismComptroller,
            abi.encodeWithSignature(
                "_setBorrowPaused(address,bool)",
                optimismWrsethMToken,
                true
            ),
            "Pause borrowing for wrsETH on Optimism",
            ActionType.Optimism
        );

        // Update oracle price feed on Optimism
        // Use addresses file instead of storage variable for consistent calldata generation
        address optimismChainlinkOracle = addresses.getAddress(
            "CHAINLINK_ORACLE"
        );
        address optimismWrsethOracleAddr = addresses.getAddress(
            "CHAINLINK_wrsETH_COMPOSITE_ORACLE"
        );
        _pushAction(
            optimismChainlinkOracle,
            abi.encodeWithSignature(
                "setFeed(string,address)",
                "wrsETH",
                optimismWrsethOracleAddr
            ),
            "Update wrsETH oracle to exchange rate feed on Optimism",
            ActionType.Optimism
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function _testMintPaused(address mToken, address underlying) internal {
        MErc20Delegator mTokenDelegator = MErc20Delegator(payable(mToken));

        uint256 mintAmount = 1e18;

        deal(underlying, address(this), mintAmount);

        IERC20(underlying).approve(mToken, mintAmount);

        vm.expectRevert("mint is paused");
        mTokenDelegator.mint(mintAmount);
    }

    function validate(Addresses addresses, address) public override {
        // ============ VALIDATE BASE CHAIN ============
        vm.selectFork(BASE_FORK_ID);

        Comptroller baseComptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        address baseWrsethMToken = addresses.getAddress("MOONWELL_wrsETH");

        // Validate minting is paused
        assertTrue(
            baseComptroller.mintGuardianPaused(baseWrsethMToken),
            "Base wrsETH minting not paused"
        );

        // Validate borrowing is paused
        assertTrue(
            baseComptroller.borrowGuardianPaused(baseWrsethMToken),
            "Base wrsETH borrowing not paused"
        );

        // Validate oracle is updated
        ChainlinkOracle baseChainlinkOracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        AggregatorV3Interface baseFeed = baseChainlinkOracle.getFeed("wrsETH");
        assertEq(
            address(baseFeed),
            addresses.getAddress("CHAINLINK_wrsETH_COMPOSITE_ORACLE"),
            "Base wrsETH oracle not updated"
        );

        // Validate price can be fetched
        (, int256 basePrice, , , ) = baseFeed.latestRoundData();
        assertGt(uint256(basePrice), 0, "Base wrsETH price check failed");

        // Test that minting is actually paused
        address baseWrsethUnderlying = MErc20(baseWrsethMToken).underlying();
        _testMintPaused(baseWrsethMToken, baseWrsethUnderlying);

        // ============ VALIDATE OPTIMISM CHAIN ============
        vm.selectFork(OPTIMISM_FORK_ID);

        Comptroller optimismComptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        address optimismWrsethMToken = addresses.getAddress("MOONWELL_wrsETH");

        // Validate minting is paused
        assertTrue(
            optimismComptroller.mintGuardianPaused(optimismWrsethMToken),
            "Optimism wrsETH minting not paused"
        );

        // Validate borrowing is paused
        assertTrue(
            optimismComptroller.borrowGuardianPaused(optimismWrsethMToken),
            "Optimism wrsETH borrowing not paused"
        );

        // Validate oracle is updated
        ChainlinkOracle optimismChainlinkOracle = ChainlinkOracle(
            addresses.getAddress("CHAINLINK_ORACLE")
        );
        AggregatorV3Interface optimismFeed = optimismChainlinkOracle.getFeed(
            "wrsETH"
        );
        assertEq(
            address(optimismFeed),
            addresses.getAddress("CHAINLINK_wrsETH_COMPOSITE_ORACLE"),
            "Optimism wrsETH oracle not updated"
        );

        // Validate price can be fetched
        (, int256 optimismPrice, , , ) = optimismFeed.latestRoundData();
        assertGt(
            uint256(optimismPrice),
            0,
            "Optimism wrsETH price check failed"
        );

        // Test that minting is actually paused
        address optimismWrsethUnderlying = MErc20(optimismWrsethMToken)
            .underlying();
        _testMintPaused(optimismWrsethMToken, optimismWrsethUnderlying);
    }
}

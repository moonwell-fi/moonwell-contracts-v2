//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import "@protocol/utils/ChainIds.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

/// @title MIP-B58: MFAM Onboarding and cbETH Incident Restitution
/// @notice Proposal to:
///         1. Transfer 310,301.6 USDC from FOUNDATION_MULTISIG (F-BASE) to C-BASE multisig
///         2. Bridge 19,095,528 WELL from F-GLMR-DEVGRANT (Moonbeam) to C-BASE multisig on Base
contract mipb58 is HybridProposal {
    using ChainIds for uint256;

    string public constant override name = "MIP-B58";

    /// @notice USDC amount to transfer from FOUNDATION_MULTISIG (310,301.6 USDC, 6 decimals)
    uint256 public constant USDC_AMOUNT = 310_301_600_000;

    /// @notice WELL amount to bridge from Moonbeam (19,095,528 WELL, 18 decimals)
    uint256 public constant WELL_AMOUNT = 19_095_528e18;

    /// @notice Pre-simulation balance snapshots
    uint256 public usdcBalanceBefore;
    uint256 public xwellBalanceBefore;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b58/b58.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        // Approve MULTICHAIN_GOVERNOR_PROXY to spend WELL from F-GLMR-DEVGRANT
        vm.startPrank(addresses.getAddress("F-GLMR-DEVGRANT"));
        IERC20(addresses.getAddress("GOVTOKEN")).approve(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            WELL_AMOUNT
        );
        vm.stopPrank();

        // Setup mock Wormhole relayer for cross-chain bridging simulation
        address router = addresses.getAddress("xWELL_ROUTER");
        uint16 wormholeChainId = BASE_CHAIN_ID.toWormholeChainId();
        uint256 realBridgeCost = xWELLRouter(router).bridgeCost(
            wormholeChainId
        );

        uint16[] memory chainIds = new uint16[](1);
        uint256[] memory prices = new uint256[](1);
        chainIds[0] = wormholeChainId;
        prices[0] = realBridgeCost;

        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter(
            chainIds,
            prices
        );
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(primaryForkId());

        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        // Approve TEMPORAL_GOVERNOR to spend USDC from FOUNDATION_MULTISIG
        vm.startPrank(addresses.getAddress("FOUNDATION_MULTISIG"));
        IERC20(addresses.getAddress("USDC")).approve(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            USDC_AMOUNT
        );
        vm.stopPrank();

        // Snapshot balances before proposal execution
        address cBase = addresses.getAddress("C-BASE");
        usdcBalanceBefore = IERC20(addresses.getAddress("USDC")).balanceOf(
            cBase
        );
        xwellBalanceBefore = IERC20(addresses.getAddress("xWELL_PROXY"))
            .balanceOf(cBase);
    }

    function build(Addresses addresses) public override {
        // ============================================================
        // Part 1: Bridge WELL from Moonbeam to Base
        // ============================================================
        vm.selectFork(MOONBEAM_FORK_ID);

        address router = addresses.getAddress("xWELL_ROUTER");
        address well = addresses.getAddress("GOVTOKEN");

        // Step 1: Transfer WELL from F-GLMR-DEVGRANT to governor
        _pushAction(
            well,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("F-GLMR-DEVGRANT"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                WELL_AMOUNT
            ),
            "Transfer 19,095,528 WELL from F-GLMR-DEVGRANT to MULTICHAIN_GOVERNOR_PROXY"
        );

        // Step 2: Approve xWELL Router to spend WELL for bridging
        _pushAction(
            well,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                router,
                WELL_AMOUNT
            ),
            "Approve xWELL Router to spend WELL",
            ActionType.Moonbeam
        );

        uint16 wormholeChainId = BASE_CHAIN_ID.toWormholeChainId();
        /// 5x buffer to account for Wormhole relay price fluctuations
        /// between proposal creation and execution
        uint256 bridgeCost = xWELLRouter(router).bridgeCost(wormholeChainId) *
            5;

        // Step 3: Bridge xWELL to Base Temporal Governor
        _pushAction(
            router,
            bridgeCost,
            abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                addresses.getAddress("TEMPORAL_GOVERNOR", BASE_CHAIN_ID),
                WELL_AMOUNT,
                wormholeChainId
            ),
            "Bridge xWELL to TEMPORAL_GOVERNOR on Base",
            ActionType.Moonbeam
        );

        vm.selectFork(BASE_FORK_ID);

        // Step 4: Transfer bridged xWELL to C-BASE multisig
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                addresses.getAddress("C-BASE"),
                WELL_AMOUNT
            ),
            "Transfer 19,095,528 xWELL to C-BASE multisig",
            ActionType.Base
        );

        // ============================================================
        // Part 2: Transfer USDC from FOUNDATION_MULTISIG to C-BASE
        // ============================================================

        // Step 5: TransferFrom USDC from FOUNDATION_MULTISIG to C-BASE
        _pushAction(
            addresses.getAddress("USDC"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("FOUNDATION_MULTISIG"),
                addresses.getAddress("C-BASE"),
                USDC_AMOUNT
            ),
            "Transfer 310,301.6 USDC from FOUNDATION_MULTISIG to C-BASE multisig",
            ActionType.Base
        );
    }

    function validate(Addresses addresses, address) public view override {
        address cBase = addresses.getAddress("C-BASE");

        // Validate xWELL transfer: balance should have increased by exactly WELL_AMOUNT
        uint256 xwellBalanceAfter = IERC20(addresses.getAddress("xWELL_PROXY"))
            .balanceOf(cBase);
        assertEq(
            xwellBalanceAfter - xwellBalanceBefore,
            WELL_AMOUNT,
            "C-BASE xWELL balance should have increased by WELL_AMOUNT"
        );

        // Validate USDC transfer: balance should have increased by exactly USDC_AMOUNT
        uint256 usdcBalanceAfter = IERC20(addresses.getAddress("USDC"))
            .balanceOf(cBase);
        assertEq(
            usdcBalanceAfter - usdcBalanceBefore,
            USDC_AMOUNT,
            "C-BASE USDC balance should have increased by USDC_AMOUNT"
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X55: Accept xWELL bridged from Ethereum mainnet
/// @notice Adds the Ethereum WormholeBridgeAdapter as a trusted sender and
///         outbound target on the existing Moonbeam, Base, and Optimism
///         adapters so they can mint/receive xWELL bridged from mainnet and
///         route outbound transfers back to Ethereum.
///
///         Executed by the Moonbeam MultichainGovernor:
///         - Moonbeam actions run directly.
///         - Base / Optimism actions are delivered to each chain's
///           TemporalGovernor via Wormhole.
///
///         The reciprocal Ethereum-side wiring + ownership handoff is handled
///         out-of-band by `script/EnableEthereumXWellBridging.s.sol` (run by
///         MOONWELL_DEPLOYER before MIP-X56).
contract mipx55 is HybridProposal {
    using ChainIds for uint256;
    using ProposalActions for *;

    string public constant override name = "MIP-X55";

    /// @notice mocked-user bridge amount used in `validate()` smoke test.
    uint256 internal constant BRIDGE_AMOUNT = 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x55/x55.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function teardown(Addresses, address) public pure override {}

    /// @notice Wire the Ethereum WormholeBridgeAdapter as a peer on each
    ///         existing chain's adapter.
    /// @dev Pushes 6 actions (2 per chain × 3 chains):
    ///        - addTrustedSenders([Ethereum]) — accept inbound VAAs from Eth
    ///        - setTargetAddresses([Ethereum]) — route outbound bridge() to Eth
    function build(Addresses addresses) public override {
        WormholeTrustedSender.TrustedSender[] memory ethPeer = _ethereumPeer(
            addresses
        );

        /// -------------------- Moonbeam --------------------
        address moonbeamAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        _pushAction(
            moonbeamAdapter,
            abi.encodeWithSignature(
                "addTrustedSenders((uint16,address)[])",
                ethPeer
            ),
            "Add Ethereum WormholeBridgeAdapter as trusted sender on Moonbeam",
            ActionType.Moonbeam
        );
        _pushAction(
            moonbeamAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                ethPeer
            ),
            "Set Ethereum as outbound bridge target on Moonbeam",
            ActionType.Moonbeam
        );

        /// ---------------------- Base ----------------------
        vm.selectFork(BASE_FORK_ID);
        address baseAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        _pushAction(
            baseAdapter,
            abi.encodeWithSignature(
                "addTrustedSenders((uint16,address)[])",
                ethPeer
            ),
            "Add Ethereum WormholeBridgeAdapter as trusted sender on Base",
            ActionType.Base
        );
        _pushAction(
            baseAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                ethPeer
            ),
            "Set Ethereum as outbound bridge target on Base",
            ActionType.Base
        );

        /// -------------------- Optimism --------------------
        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        _pushAction(
            optimismAdapter,
            abi.encodeWithSignature(
                "addTrustedSenders((uint16,address)[])",
                ethPeer
            ),
            "Add Ethereum WormholeBridgeAdapter as trusted sender on Optimism",
            ActionType.Optimism
        );
        _pushAction(
            optimismAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                ethPeer
            ),
            "Set Ethereum as outbound bridge target on Optimism",
            ActionType.Optimism
        );

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        address ethBridgeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            ETHEREUM_CHAIN_ID
        );

        // Moonbeam — wiring only. Moonbeam has no on-chain quoter, so the
        // 3-arg bridge() overload always reverts there. Outbound smoke-testing
        // would require the signed-quote overload + mock executor, which is
        // out of scope for this proposal's validation.
        _assertEthereumPeerWired(
            WormholeBridgeAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ),
            ethBridgeAdapter,
            "Moonbeam"
        );

        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter baseAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        _assertEthereumPeerWired(baseAdapter, ethBridgeAdapter, "Base");
        _runMockedUserBridge(addresses, baseAdapter, "Base");

        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter optimismAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        _assertEthereumPeerWired(optimismAdapter, ethBridgeAdapter, "Optimism");
        _runMockedUserBridge(addresses, optimismAdapter, "Optimism");

        vm.selectFork(primaryForkId());
    }

    function _ethereumPeer(
        Addresses addresses
    )
        internal
        view
        returns (WormholeTrustedSender.TrustedSender[] memory peer)
    {
        peer = new WormholeTrustedSender.TrustedSender[](1);
        peer[0] = WormholeTrustedSender.TrustedSender({
            chainId: ETHEREUM_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                ETHEREUM_CHAIN_ID
            )
        });
    }

    function _assertEthereumPeerWired(
        WormholeBridgeAdapter adapter,
        address ethBridgeAdapter,
        string memory chainLabel
    ) internal view {
        require(
            adapter.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                ethBridgeAdapter
            ),
            string.concat(
                "MIP-X55: ",
                chainLabel,
                " adapter does not trust Ethereum peer"
            )
        );
        require(
            adapter.targetAddress(ETHEREUM_WORMHOLE_CHAIN_ID) ==
                ethBridgeAdapter,
            string.concat(
                "MIP-X55: ",
                chainLabel,
                " adapter targetAddress[Eth] mismatch"
            )
        );
    }

    /// @notice Funds a synthetic user with xWELL + ETH and exercises the
    ///         on-chain-quote bridge() overload with Ethereum as the
    ///         destination. Confirms the newly-wired Ethereum target
    ///         actually routes through the executor and that the burn
    ///         path still works (buffer + rate limit untouched).
    ///         Mirrors `mip-x53.sol#_runMockedUserBridge`.
    function _runMockedUserBridge(
        Addresses addresses,
        WormholeBridgeAdapter adapter,
        string memory chainName
    ) internal {
        uint256 cost = adapter.bridgeCost(ETHEREUM_WORMHOLE_CHAIN_ID);
        assertGt(
            cost,
            0,
            string.concat(
                chainName,
                ": bridgeCost(Ethereum) returned 0 after MIP-X55 wiring"
            )
        );

        address user = address(0xBEEF);
        IERC20 xWell = IERC20(addresses.getAddress("xWELL_PROXY"));

        /// Mint synthetic xWELL balance to user (`deal` writes balance + totalSupply)
        deal(address(xWell), user, BRIDGE_AMOUNT, true);

        /// Fund user with exactly the on-chain quote
        vm.deal(user, cost);

        uint256 userBalanceBefore = xWell.balanceOf(user);
        uint256 totalSupplyBefore = xWell.totalSupply();

        vm.startPrank(user);
        xWell.approve(address(adapter), BRIDGE_AMOUNT);
        adapter.bridge{value: cost}(
            uint256(ETHEREUM_WORMHOLE_CHAIN_ID),
            BRIDGE_AMOUNT,
            user
        );
        vm.stopPrank();

        assertEq(
            userBalanceBefore - xWell.balanceOf(user),
            BRIDGE_AMOUNT,
            string.concat(chainName, ": user xWELL not burned by bridge()")
        );
        assertEq(
            totalSupplyBefore - xWell.totalSupply(),
            BRIDGE_AMOUNT,
            string.concat(chainName, ": xWELL totalSupply not reduced")
        );
    }
}

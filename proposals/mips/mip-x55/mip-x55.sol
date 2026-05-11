//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_FORK_ID, ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X55: Enable xWELL bridging on Ethereum mainnet
/// @notice Wires the Ethereum WormholeBridgeAdapter to bridge xWELL with
///         Moonbeam, Base, and Optimism by registering each peer adapter as a
///         trusted sender and outbound target.
///
///         Execution prerequisites (handled by
///         `script/TransferEthereumXWellOwnership.s.sol`):
///         1. MOONWELL_DEPLOYER calls `transferOwnership(FOUNDATION_MULTISIG)`
///            on xWELL_PROXY and WORMHOLE_BRIDGE_ADAPTER_PROXY.
///         2. FOUNDATION_MULTISIG calls `acceptOwnership()` on both (Ownable2Step).
///
///         This proposal is executed directly by FOUNDATION_MULTISIG as Safe
///         transactions — it does NOT route through MultichainGovernor because
///         Ethereum governance only goes live in MIP-X56.
contract mipx55 is HybridProposal {
    using ChainIds for uint256;

    string public constant override name = "MIP-X55";

    /// @notice Raw multisig-executable steps. Each entry maps 1:1 to a Safe
    ///         transaction. Kept separate from `actions` (governance queue) so
    ///         we can print/simulate without going through MultichainGovernor.
    struct MultisigCall {
        address target;
        bytes data;
        string description;
    }

    MultisigCall[] internal _multisigCalls;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x55/x55.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        initProposal(addresses);

        if (DO_BUILD) build(addresses);
        if (DO_RUN) simulate(addresses, address(0));
        if (DO_VALIDATE) {
            validate(addresses, address(0));
            console.log("Validation completed for proposal ", this.name());
        }
        if (DO_PRINT) {
            _printMultisigCalls();
        }
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function teardown(Addresses, address) public pure override {}

    /// @notice Build the bridge wiring as multisig-executable calls.
    /// @dev We construct one (chainId, peerAddress) tuple per remote chain
    ///      (Moonbeam, Base, Optimism), then issue both `addTrustedSenders` and
    ///      `setTargetAddresses` against the Ethereum adapter. Inbound trust
    ///      (addTrustedSenders) is checked on VAA receipt; outbound routing
    ///      (setTargetAddresses) is read on `bridge()`. Both must be set or
    ///      bridging is half-open.
    function build(Addresses addresses) public override {
        address ethBridgeAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );

        WormholeTrustedSender.TrustedSender[]
            memory peers = new WormholeTrustedSender.TrustedSender[](3);

        peers[0] = WormholeTrustedSender.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                MOONBEAM_CHAIN_ID
            )
        });
        peers[1] = WormholeTrustedSender.TrustedSender({
            chainId: BASE_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                BASE_CHAIN_ID
            )
        });
        peers[2] = WormholeTrustedSender.TrustedSender({
            chainId: OPTIMISM_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                OPTIMISM_CHAIN_ID
            )
        });

        _multisigCalls.push(
            MultisigCall({
                target: ethBridgeAdapter,
                data: abi.encodeWithSignature(
                    "addTrustedSenders((uint16,address)[])",
                    peers
                ),
                description: "Whitelist Moonbeam/Base/Optimism WormholeBridgeAdapter as trusted senders on Ethereum"
            })
        );

        _multisigCalls.push(
            MultisigCall({
                target: ethBridgeAdapter,
                data: abi.encodeWithSignature(
                    "setTargetAddresses((uint16,address)[])",
                    peers
                ),
                description: "Set outbound bridge target addresses for Moonbeam/Base/Optimism on Ethereum"
            })
        );
    }

    /// @notice Execute the multisig calls under a prank from FOUNDATION_MULTISIG.
    function simulate(Addresses addresses, address) public override {
        address multisig = addresses.getAddress("FOUNDATION_MULTISIG");

        // Defensive: the bridge adapter must already be owned by the multisig.
        // If this fails, run `script/TransferEthereumXWellOwnership.s.sol` first
        // and have the multisig call `acceptOwnership()`.
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        require(
            adapter.owner() == multisig,
            "MIP-X55: WormholeBridgeAdapter not owned by FOUNDATION_MULTISIG; run TransferEthereumXWellOwnership first"
        );

        for (uint256 i = 0; i < _multisigCalls.length; i++) {
            vm.prank(multisig);
            (bool ok, bytes memory ret) = _multisigCalls[i].target.call(
                _multisigCalls[i].data
            );
            require(ok, string(ret));
        }
    }

    function validate(Addresses addresses, address) public override {
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        _assertPeerWired(
            adapter,
            addresses,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            MOONBEAM_CHAIN_ID,
            "Moonbeam"
        );
        _assertPeerWired(
            adapter,
            addresses,
            BASE_WORMHOLE_CHAIN_ID,
            BASE_CHAIN_ID,
            "Base"
        );
        _assertPeerWired(
            adapter,
            addresses,
            OPTIMISM_WORMHOLE_CHAIN_ID,
            OPTIMISM_CHAIN_ID,
            "Optimism"
        );
    }

    function _assertPeerWired(
        WormholeBridgeAdapter adapter,
        Addresses addresses,
        uint16 wormholeChainId,
        uint256 chainId,
        string memory label
    ) internal view {
        address peer = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            chainId
        );
        require(
            adapter.isTrustedSender(wormholeChainId, peer),
            string.concat("MIP-X55: ", label, " peer not in trustedSenders")
        );
        require(
            adapter.targetAddress(wormholeChainId) == peer,
            string.concat("MIP-X55: ", label, " peer not in targetAddress map")
        );
    }

    /// @notice Print each multisig call as `to=<addr> data=0x...` so the
    ///         FOUNDATION_MULTISIG signer can build the Safe transaction batch.
    function _printMultisigCalls() internal view {
        console.log(
            "\n=== MIP-X55: Calldata for FOUNDATION_MULTISIG to execute ==="
        );
        for (uint256 i = 0; i < _multisigCalls.length; i++) {
            console.log("--- Call ---");
            console.log("description:", _multisigCalls[i].description);
            console.log("to:        ", _multisigCalls[i].target);
            console.log("value:      0");
            console.log("data:");
            console.logBytes(_multisigCalls[i].data);
        }
    }
}

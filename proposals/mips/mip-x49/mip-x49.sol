//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X49: Fix Wormhole Consistency Level (200 -> 1)
/// @notice Upgrades WormholeBridgeAdapter on Moonbeam, Base, and Optimism,
///         MultichainGovernor on Moonbeam, and MultichainVoteCollection on
///         Base and Optimism to fix CONSISTENCY_LEVEL from 200 (instant) to
///         1 (finalized).
contract mipx49 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X49";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x49/x49.md")
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
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        /// -------------------------------------------------------
        /// Deploy WormholeBridgeAdapter V4 impls
        /// -------------------------------------------------------

        /// Moonbeam: deploy WormholeUnwrapperAdapter (restores unwrap
        /// behavior that was lost when mip-x48 mistakenly upgraded to
        /// plain WormholeBridgeAdapter)
        vm.selectFork(primaryForkId());
        if (!addresses.isAddressSet("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address impl = address(new WormholeUnwrapperAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V4", impl);
        }

        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4", impl);
        }

        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4", impl);
        }

        /// -------------------------------------------------------
        /// Deploy MultichainGovernor V3 impl (Moonbeam only)
        /// -------------------------------------------------------

        vm.selectFork(primaryForkId());
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new MultichainGovernor());
            vm.stopBroadcast();
            addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL_V3", impl);
        }

        /// -------------------------------------------------------
        /// Deploy MultichainVoteCollection V3 impls (Base + Optimism)
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("VOTE_COLLECTION_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new MultichainVoteCollection());
            vm.stopBroadcast();
            addresses.addAddress("VOTE_COLLECTION_IMPL_V3", impl);
        }

        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("VOTE_COLLECTION_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new MultichainVoteCollection());
            vm.stopBroadcast();
            addresses.addAddress("VOTE_COLLECTION_IMPL_V3", impl);
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        /// -------------------------------------------------------
        /// Moonbeam: WormholeUnwrapperAdapter + MultichainGovernor
        /// -------------------------------------------------------

        vm.selectFork(primaryForkId());
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V4")
            ),
            "Upgrade to WormholeUnwrapperAdapter on Moonbeam (fix mip-x48)"
        );

        /// Re-set the lockbox after upgrading to WormholeUnwrapperAdapter.
        /// The original lockbox was at slot 156, but mip-x48's initializeV3
        /// overwrote it with the wormhole core address. The new layout puts
        /// lockbox at slot 158 (after wormhole + processedVAAHashes), which
        /// is empty and needs to be initialized.
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setLockbox(address)",
                addresses.getAddress("xWELL_LOCKBOX")
            ),
            "Re-set lockbox on Moonbeam unwrapper (storage lost during x48)"
        );

        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL_V3")
            ),
            "Upgrade MultichainGovernor on Moonbeam"
        );

        /// -------------------------------------------------------
        /// Base: WormholeBridgeAdapter + MultichainVoteCollection
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")
            ),
            "Upgrade WormholeBridgeAdapter on Base"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL_V3")
            ),
            "Upgrade MultichainVoteCollection on Base"
        );

        /// -------------------------------------------------------
        /// Optimism: WormholeBridgeAdapter + MultichainVoteCollection
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")
            ),
            "Upgrade WormholeBridgeAdapter on Optimism"
        );

        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL_V3")
            ),
            "Upgrade MultichainVoteCollection on Optimism"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());
        _validateAdapter(addresses, "Moonbeam");
        _validateMoonbeamUnwrapper(addresses);
        _validateGovernor(addresses);

        vm.selectFork(BASE_FORK_ID);
        _validateAdapter(addresses, "Base");
        _validateVoteCollection(addresses, "Base");

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateAdapter(addresses, "Optimism");
        _validateVoteCollection(addresses, "Optimism");

        vm.selectFork(primaryForkId());
    }

    /// @notice Validate that the Moonbeam adapter is the unwrapper variant
    ///         and the lockbox storage survived the x48 upgrade round-trip.
    function _validateMoonbeamUnwrapper(Addresses addresses) internal view {
        WormholeUnwrapperAdapter unwrapper = WormholeUnwrapperAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        assertEq(
            unwrapper.lockbox(),
            addresses.getAddress("xWELL_LOCKBOX"),
            "Moonbeam: unwrapper lockbox not set (storage lost during x48)"
        );
    }

    function _validateAdapter(
        Addresses addresses,
        string memory chainName
    ) internal view {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address expectedImpl;
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            expectedImpl = addresses.getAddress(
                "WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V4"
            );
        } else {
            expectedImpl = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V4"
            );
        }
        string memory proxyAdminKey = block.chainid == MOONBEAM_CHAIN_ID
            ? "MOONBEAM_PROXY_ADMIN"
            : "MRD_PROXY_ADMIN";
        address proxyAdmin = addresses.getAddress(proxyAdminKey);

        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(chainName, ": adapter not upgraded to V4")
        );

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);
        assertEq(
            adapter.CONSISTENCY_LEVEL(),
            1,
            string.concat(chainName, ": adapter CONSISTENCY_LEVEL should be 1")
        );

        assertTrue(
            address(adapter.wormhole()) != address(0),
            string.concat(chainName, ": adapter wormhole core not set")
        );
        assertTrue(
            address(adapter.xERC20()) != address(0),
            string.concat(chainName, ": adapter xERC20 not set")
        );
        assertEq(
            adapter.gasLimit(),
            300_000,
            string.concat(chainName, ": adapter gasLimit changed")
        );

        // Verify bridgeCost returns only messageFee (no relayer quote)
        assertEq(
            adapter.bridgeCost(0),
            adapter.wormhole().messageFee(),
            string.concat(chainName, ": bridgeCost should equal messageFee")
        );
    }

    function _validateGovernor(Addresses addresses) internal view {
        address proxy = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address expectedImpl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_IMPL_V3"
        );
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(actualImpl, expectedImpl, "governor not upgraded to V3");

        MultichainGovernor gov = MultichainGovernor(payable(proxy));
        assertEq(
            gov.CONSISTENCY_LEVEL(),
            1,
            "governor CONSISTENCY_LEVEL should be 1"
        );
        assertTrue(
            address(gov.wormhole()) != address(0),
            "governor wormhole core not set"
        );
        assertEq(
            gov.bridgeCost(0),
            gov.wormhole().messageFee(),
            "governor bridgeCost should equal messageFee"
        );
    }

    function _validateVoteCollection(
        Addresses addresses,
        string memory chainName
    ) internal view {
        address proxy = addresses.getAddress("VOTE_COLLECTION_PROXY");
        address expectedImpl = addresses.getAddress("VOTE_COLLECTION_IMPL_V3");
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(chainName, ": voteCollection not upgraded to V3")
        );

        MultichainVoteCollection vc = MultichainVoteCollection(proxy);
        assertEq(
            vc.CONSISTENCY_LEVEL(),
            1,
            string.concat(
                chainName,
                ": voteCollection CONSISTENCY_LEVEL should be 1"
            )
        );
        assertTrue(
            address(vc.wormhole()) != address(0),
            string.concat(chainName, ": voteCollection wormhole core not set")
        );
        assertEq(
            vc.bridgeCost(0),
            vc.wormhole().messageFee(),
            string.concat(
                chainName,
                ": voteCollection bridgeCost should equal messageFee"
            )
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X48: Upgrade WormholeBridgeAdapter and WormholeBridgeBase for Direct VAA Verification - this impacts
///        xWELL, MultichainGovernor, and MultichainVoteCollection
/// @author Moonwell Contributors
/// @notice Proposal to upgrade xWELL on Moonbeam, Base, and Optimism
///         to V3 with direct Wormhole guardian-signed VAA verification via processVAA(),
///         replacing dependency on the deprecated Wormhole standard relayer. We also upgrade MultichainGovernor on
///         Moonbeam, and MultichainVoteCollection on Base and Optimism.
///         update the pause guardian on all chains to the new security council safes. Also upgrades
///         NOTE: Ethereum xWELL deployment is still deployer-owned (until governor migration) so that upgrade
///         should be done via UpgradeWormholeAdapterEthereum.
contract mipx48 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X48";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x48/x48.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
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

    function deploy(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());

        // Moonbeam
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
        }

        // Base
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
        }

        // Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
        }

        /// -------------------------------------------------------
        /// Deploy MultichainGovernor + MultichainVoteCollection impls
        /// -------------------------------------------------------

        // Moonbeam: MultichainGovernor
        vm.selectFork(primaryForkId());
        if (!addresses.isAddressSet("MULTICHAIN_GOVERNOR_IMPL_V2")) {
            vm.startBroadcast();
            address govImpl = address(new MultichainGovernor());
            vm.stopBroadcast();
            addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL_V2", govImpl);
        }

        // Base: MultichainVoteCollection
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("VOTE_COLLECTION_IMPL_V2")) {
            vm.startBroadcast();
            address vcImpl = address(new MultichainVoteCollection());
            vm.stopBroadcast();
            addresses.addAddress("VOTE_COLLECTION_IMPL_V2", vcImpl);
        }

        // Optimism: MultichainVoteCollection
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("VOTE_COLLECTION_IMPL_V2")) {
            vm.startBroadcast();
            address vcImpl = address(new MultichainVoteCollection());
            vm.stopBroadcast();
            addresses.addAddress("VOTE_COLLECTION_IMPL_V2", vcImpl);
        }

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        vm.selectFork(primaryForkId());

        // Moonbeam: upgrade WormholeBridgeAdapter proxy with initializeV3
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade WormholeBridgeAdapter on Moonbeam with initializeV3"
        );

        // Base: upgrade WormholeBridgeAdapter proxy with initializeV3
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade WormholeBridgeAdapter on Base with initializeV3"
        );

        // Optimism: upgrade WormholeBridgeAdapter proxy with initializeV3
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade WormholeBridgeAdapter on Optimism with initializeV3"
        );

        /// -------------------------------------------------------
        /// Update xWELL pause guardian on all chains
        /// -------------------------------------------------------

        // Moonbeam: update xWELL pause guardian
        vm.selectFork(primaryForkId());
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Update xWELL pause guardian on Moonbeam"
        );

        // Base: update xWELL pause guardian
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Update xWELL pause guardian on Base"
        );

        // Optimism: update xWELL pause guardian
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Update xWELL pause guardian on Optimism"
        );

        // NOTE: Ethereum xWELL is deployer-owned, not governed by MultichainGovernor.
        // The Ethereum pause guardian update must be done separately via the deployer.

        /// -------------------------------------------------------
        /// Upgrade MultichainGovernor + MultichainVoteCollection
        /// -------------------------------------------------------

        // Base: upgrade MultichainVoteCollection with initializeV2
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL_V2"),
                abi.encodeWithSignature(
                    "initializeV2(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade MultichainVoteCollection on Base with initializeV2"
        );

        // Optimism: upgrade MultichainVoteCollection with initializeV2
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL_V2"),
                abi.encodeWithSignature(
                    "initializeV2(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade MultichainVoteCollection on Optimism with initializeV2"
        );

        // Moonbeam: upgrade MultichainGovernor with initializeV2
        vm.selectFork(primaryForkId());
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL_V2"),
                abi.encodeWithSignature(
                    "initializeV2(address)",
                    addresses.getAddress("WORMHOLE_CORE")
                )
            ),
            "Upgrade MultichainGovernor on Moonbeam with initializeV2"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        // Validate Moonbeam
        vm.selectFork(primaryForkId());
        _validateChainUpgrade(addresses, "Moonbeam");
        _validatePauseGuardian(addresses, "Moonbeam");

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateChainUpgrade(addresses, "Base");
        _validatePauseGuardian(addresses, "Base");

        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChainUpgrade(addresses, "Optimism");
        _validatePauseGuardian(addresses, "Optimism");

        /// -------------------------------------------------------
        /// Validate MultichainGovernor + MultichainVoteCollection
        /// -------------------------------------------------------

        // Validate Governor on Moonbeam
        vm.selectFork(primaryForkId());
        _validateGovernorUpgrade(addresses, "Moonbeam");

        // Validate VoteCollection on Base
        vm.selectFork(BASE_FORK_ID);
        _validateVoteCollectionUpgrade(addresses, "Base");

        // Validate VoteCollection on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateVoteCollectionUpgrade(addresses, "Optimism");

        // NOTE: Ethereum xWELL pause guardian + bridge adapter upgrade
        // is handled separately via UpgradeWormholeAdapterEthereum.

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    /// @notice Validate the WormholeBridgeAdapter upgrade on a single chain
    /// @param addresses The addresses contract
    /// @param chainName Human-readable chain name for error messages
    function _validateChainUpgrade(
        Addresses addresses,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address expectedImpl = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"
        );
        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");
        string memory proxyAdminKey = block.chainid == MOONBEAM_CHAIN_ID
            ? "MOONBEAM_PROXY_ADMIN"
            : "MRD_PROXY_ADMIN";
        address proxyAdmin = addresses.getAddress(proxyAdminKey);

        // 1. Verify proxy implementation is set to V3
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(
                chainName,
                ": WormholeBridgeAdapter proxy not upgraded to V3"
            )
        );

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);

        // 2. Verify wormhole core is set
        assertEq(
            address(adapter.wormhole()),
            wormholeCore,
            string.concat(chainName, ": wormhole core not set correctly")
        );

        // 3. Verify old state preserved: gasLimit == 300_000
        assertEq(
            adapter.gasLimit(),
            300_000,
            string.concat(chainName, ": gasLimit changed after upgrade")
        );

        // 4. Verify wormholeRelayer is not zero (legacy relayer still set)
        assertTrue(
            address(adapter.wormholeRelayer()) != address(0),
            string.concat(chainName, ": wormholeRelayer should not be zero")
        );

        // 5. Verify xERC20 token address preserved
        assertEq(
            address(adapter.xERC20()),
            addresses.getAddress("xWELL_PROXY"),
            string.concat(chainName, ": xERC20 corrupted after upgrade")
        );

        // 6. Verify all trusted senders still registered (every other chain)
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            assertTrue(
                adapter.isTrustedSender(BASE_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Base trusted sender missing")
            );
            assertTrue(
                adapter.isTrustedSender(OPTIMISM_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Optimism trusted sender missing")
            );
        } else if (block.chainid == BASE_CHAIN_ID) {
            assertTrue(
                adapter.isTrustedSender(MOONBEAM_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Moonbeam trusted sender missing")
            );
            assertTrue(
                adapter.isTrustedSender(OPTIMISM_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Optimism trusted sender missing")
            );
        } else if (block.chainid == OPTIMISM_CHAIN_ID) {
            assertTrue(
                adapter.isTrustedSender(MOONBEAM_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Moonbeam trusted sender missing")
            );
            assertTrue(
                adapter.isTrustedSender(BASE_WORMHOLE_CHAIN_ID, proxy),
                string.concat(chainName, ": Base trusted sender missing")
            );
        }

        // 7. Verify owner preserved
        string memory ownerKey = block.chainid == MOONBEAM_CHAIN_ID
            ? "MULTICHAIN_GOVERNOR_PROXY"
            : "TEMPORAL_GOVERNOR";
        assertEq(
            adapter.owner(),
            addresses.getAddress(ownerKey),
            string.concat(chainName, ": owner changed after upgrade")
        );

        // 8. Verify Wormhole core messageFee is 0 (bridge-out cost assumption)
        assertEq(
            IWormhole(wormholeCore).messageFee(),
            0,
            string.concat(
                chainName,
                ": Wormhole messageFee is non-zero - bridgeCost assumption violated"
            )
        );

        // 9. Verify initializeV3 cannot be called again (reinitializer guard)
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(address(1));
    }

    /// @notice Validate xWELL pause guardian was updated on a chain
    function _validatePauseGuardian(
        Addresses addresses,
        string memory chainName
    ) internal view {
        xWELL xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
        address expectedGuardian = addresses.getAddress("PAUSE_GUARDIAN");

        assertEq(
            xwellProxy.pauseGuardian(),
            expectedGuardian,
            string.concat(
                chainName,
                ": xWELL pause guardian not updated correctly"
            )
        );
    }

    /// @notice Validate MultichainGovernor upgrade
    function _validateGovernorUpgrade(
        Addresses addresses,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY");
        address expectedImpl = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_IMPL_V2"
        );
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        // Verify proxy implementation is set to V2
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(
                chainName,
                ": MultichainGovernor proxy not upgraded to V2"
            )
        );

        MultichainGovernor gov = MultichainGovernor(payable(proxy));
        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        assertEq(
            address(gov.wormhole()),
            wormholeCore,
            string.concat(chainName, ": governor wormhole not set")
        );

        vm.expectRevert("Initializable: contract is already initialized");
        gov.initializeV2(address(1));
    }

    /// @notice Validate MultichainVoteCollection upgrade
    function _validateVoteCollectionUpgrade(
        Addresses addresses,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("VOTE_COLLECTION_PROXY");
        address expectedImpl = addresses.getAddress("VOTE_COLLECTION_IMPL_V2");
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

        // Verify proxy implementation is set to V2
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(
                chainName,
                ": MultichainVoteCollection proxy not upgraded to V2"
            )
        );

        MultichainVoteCollection vc = MultichainVoteCollection(proxy);
        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        assertEq(
            address(vc.wormhole()),
            wormholeCore,
            string.concat(chainName, ": voteCollection wormhole not set")
        );

        vm.expectRevert("Initializable: contract is already initialized");
        vc.initializeV2(address(1));
    }
}

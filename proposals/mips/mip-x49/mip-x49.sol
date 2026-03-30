//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X49: Fix xWELL WormholeBridgeAdapter Consistency Level
/// @notice Upgrades WormholeBridgeAdapter on Moonbeam, Base, and Optimism to
///         fix the Wormhole consistency level from 200 (instant) to 1 (finalized).
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

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        // Deploy new WormholeBridgeAdapter impl on each chain
        // (CONSISTENCY_LEVEL = 1 baked into bytecode)

        vm.selectFork(primaryForkId());
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V4",
                implementation
            );
        }

        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V4",
                implementation
            );
        }

        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V4",
                implementation
            );
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        // Moonbeam: upgrade WormholeBridgeAdapter proxy (no reinitializer needed)
        vm.selectFork(primaryForkId());
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")
            ),
            "Upgrade WormholeBridgeAdapter on Moonbeam to fix consistency level"
        );

        // Moonbeam: re-grant xWELL pause guardian (consumed after pause/unpause)
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Re-grant xWELL pause guardian on Moonbeam"
        );

        // Base: upgrade WormholeBridgeAdapter proxy
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")
            ),
            "Upgrade WormholeBridgeAdapter on Base to fix consistency level"
        );

        // Base: re-grant xWELL pause guardian (consumed after pause/unpause)
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Re-grant xWELL pause guardian on Base"
        );

        // Optimism: upgrade WormholeBridgeAdapter proxy
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V4")
            ),
            "Upgrade WormholeBridgeAdapter on Optimism to fix consistency level"
        );

        // Optimism: re-grant xWELL pause guardian (consumed after pause/unpause)
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "grantPauseGuardian(address)",
                addresses.getAddress("PAUSE_GUARDIAN")
            ),
            "Re-grant xWELL pause guardian on Optimism"
        );
    }

    /// @notice Simulate the pause/unpause that will happen before this proposal
    ///         executes on-chain. xWELL will be paused after x48 to prevent
    ///         bridging with instant finality, then unpaused before x49.
    ///         This consumes the pause guardian on each chain.
    function beforeSimulationHook(Addresses addresses) public override {
        uint256[] memory forks = new uint256[](3);
        forks[0] = MOONBEAM_FORK_ID;
        forks[1] = BASE_FORK_ID;
        forks[2] = OPTIMISM_FORK_ID;

        for (uint256 i = 0; i < forks.length; i++) {
            vm.selectFork(forks[i]);

            xWELL xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
            address guardian = xwellProxy.pauseGuardian();

            // Only pause/unpause if guardian is still set (not already consumed)
            if (guardian != address(0) && !xwellProxy.pauseUsed()) {
                vm.prank(guardian);
                xwellProxy.pause();

                vm.prank(guardian);
                xwellProxy.unpause();
            }
        }

        vm.selectFork(primaryForkId());
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());
        _validateChain(addresses, "Moonbeam");

        vm.selectFork(BASE_FORK_ID);
        _validateChain(addresses, "Base");

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChain(addresses, "Optimism");

        vm.selectFork(primaryForkId());
    }

    function _validateChain(
        Addresses addresses,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address expectedImpl = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_IMPL_V4"
        );
        string memory proxyAdminKey = block.chainid == MOONBEAM_CHAIN_ID
            ? "MOONBEAM_PROXY_ADMIN"
            : "MRD_PROXY_ADMIN";
        address proxyAdmin = addresses.getAddress(proxyAdminKey);

        // Verify proxy implementation is set to V4
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(proxy)
        );
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(
                chainName,
                ": WormholeBridgeAdapter proxy not upgraded to V4"
            )
        );

        // Verify consistency level is 1
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);
        assertEq(
            adapter.CONSISTENCY_LEVEL(),
            1,
            string.concat(chainName, ": CONSISTENCY_LEVEL should be 1")
        );

        // Verify adapter state preserved
        assertTrue(
            address(adapter.wormhole()) != address(0),
            string.concat(chainName, ": wormhole core should be set")
        );
        assertTrue(
            address(adapter.xERC20()) != address(0),
            string.concat(chainName, ": xERC20 should be set")
        );
        assertEq(
            adapter.gasLimit(),
            300_000,
            string.concat(chainName, ": gasLimit should be preserved")
        );

        // Verify xWELL pause guardian re-granted
        xWELL xwellProxy = xWELL(addresses.getAddress("xWELL_PROXY"));
        assertEq(
            xwellProxy.pauseGuardian(),
            addresses.getAddress("PAUSE_GUARDIAN"),
            string.concat(chainName, ": xWELL pause guardian not re-granted")
        );
    }
}

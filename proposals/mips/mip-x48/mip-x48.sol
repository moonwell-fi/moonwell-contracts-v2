//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {MockWormholeCore} from "@test/mock/MockWormholeCore.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {Address} from "@utils/Address.sol";

/// @title MIP-X48: Upgrade WormholeBridgeAdapter for Direct VAA Verification
/// @author Moonwell Contributors
/// @notice Proposal to upgrade WormholeBridgeAdapter on Moonbeam, Base, and Optimism
///         to V3 with direct Wormhole guardian-signed VAA verification via processVAA(),
///         replacing dependency on the deprecated Wormhole standard relayer.
contract mipx48 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;
    using Address for address;

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
        if (DO_RUN) run(addresses, deployerAddress);
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
        // Moonbeam
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
            vm.stopBroadcast();
        }

        // Base
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
            vm.stopBroadcast();
        }

        // Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address implementation = address(new WormholeBridgeAdapter());
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3",
                implementation
            );
            vm.stopBroadcast();
        }

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
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

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        // Validate Moonbeam
        vm.selectFork(primaryForkId());
        _validateChainUpgrade(
            addresses,
            "Moonbeam",
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            MOONBEAM_WORMHOLE_CHAIN_ID
        );

        // Validate Base
        vm.selectFork(BASE_FORK_ID);
        _validateChainUpgrade(
            addresses,
            "Base",
            addresses.getAddress("MRD_PROXY_ADMIN"),
            BASE_WORMHOLE_CHAIN_ID
        );

        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChainUpgrade(
            addresses,
            "Optimism",
            addresses.getAddress("MRD_PROXY_ADMIN"),
            OPTIMISM_WORMHOLE_CHAIN_ID
        );

        // Switch back to primary fork
        vm.selectFork(primaryForkId());
    }

    /// @notice Validate the WormholeBridgeAdapter upgrade on a single chain
    /// @param addresses The addresses contract
    /// @param chainName Human-readable chain name for error messages
    /// @param proxyAdmin The proxy admin address on this chain
    /// @param wormholeChainId The Wormhole chain ID for this chain (used in processVAA test)
    function _validateChainUpgrade(
        Addresses addresses,
        string memory chainName,
        address proxyAdmin,
        uint16 wormholeChainId
    ) internal {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address expectedImpl = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"
        );
        address wormholeCore = addresses.getAddress("WORMHOLE_CORE");

        // 1. Verify proxy implementation updated
        address actualImpl = _getProxyImplementation(proxyAdmin, proxy);
        assertEq(
            actualImpl,
            expectedImpl,
            string.concat(
                chainName,
                ": WormholeBridgeAdapter implementation not upgraded"
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

        // 5. Verify initializeV3 cannot be called again (reinitializer guard)
        vm.expectRevert();
        adapter.initializeV3(address(1));

        // 6. Verify processVAA works with MockWormholeCore
        _validateProcessVAA(
            addresses,
            adapter,
            proxy,
            wormholeCore,
            chainName,
            wormholeChainId
        );
    }

    /// @notice Test processVAA by deploying a MockWormholeCore, etching it onto the
    ///         WORMHOLE_CORE address, and calling processVAA with a valid emitter/payload
    function _validateProcessVAA(
        Addresses addresses,
        WormholeBridgeAdapter adapter,
        address proxy,
        address wormholeCore,
        string memory chainName,
        uint16 wormholeChainId
    ) internal {
        // Deploy MockWormholeCore and etch it onto the real wormhole core address
        MockWormholeCore mockCore = new MockWormholeCore();
        vm.etch(wormholeCore, address(mockCore).code);

        // Set up the mock: valid=true, emitter is the adapter itself on a
        // different chain (simulate cross-chain bridge).
        // We use a source chain that the adapter trusts.
        // Pick a wormhole chain ID different from the current chain.
        uint16 sourceChainId;
        if (wormholeChainId == MOONBEAM_WORMHOLE_CHAIN_ID) {
            sourceChainId = BASE_WORMHOLE_CHAIN_ID;
        } else {
            sourceChainId = MOONBEAM_WORMHOLE_CHAIN_ID;
        }

        // The emitter address must be the WormholeBridgeAdapter on the source chain.
        // Since all chains share the same adapter proxy address, use that as emitter.
        bytes32 emitterAddr = proxy.toBytes();

        address recipient = address(0xCAFE);
        uint256 bridgeAmount = 1e18;

        // Configure mock to return valid VM with the adapter as trusted sender
        MockWormholeCore(wormholeCore).setStorage(
            true, // valid
            sourceChainId,
            emitterAddr,
            "", // no reason needed when valid
            abi.encode(recipient, bridgeAmount)
        );

        // Get xWELL balance before
        address xwellProxy = addresses.getAddress("xWELL_PROXY");
        uint256 balanceBefore = xWELL(xwellProxy).balanceOf(recipient);

        // Call processVAA with arbitrary bytes (mock ignores actual VAA content)
        adapter.processVAA(bytes("mock_vaa_data"));

        // Verify tokens were minted
        uint256 balanceAfter = xWELL(xwellProxy).balanceOf(recipient);
        assertEq(
            balanceAfter,
            balanceBefore + bridgeAmount,
            string.concat(
                chainName,
                ": processVAA did not mint expected tokens"
            )
        );

        // Verify replay protection: calling again with same data should revert
        vm.expectRevert("WormholeBridgeAdapter: VAA already processed");
        adapter.processVAA(bytes("mock_vaa_data"));
    }

    /// @notice Read proxy implementation via ProxyAdmin.getProxyImplementation
    function _getProxyImplementation(
        address proxyAdmin,
        address proxy
    ) internal view returns (address) {
        (bool success, bytes memory data) = proxyAdmin.staticcall(
            abi.encodeWithSignature("getProxyImplementation(address)", proxy)
        );
        require(success, "Failed to get proxy implementation");
        return abi.decode(data, (address));
    }
}

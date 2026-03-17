//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X48: Upgrade xWELL WormholeBridgeAdapter to Executor Framework
/// @author Moonwell Contributors
/// @notice Upgrades the WormholeBridgeAdapter proxy on Moonbeam, Base, and Optimism
///         from the deprecated Standard Relayer to the new Wormhole Executor framework.
///         Each proxy is upgraded via upgradeAndCall with initializeV3.
///         Ethereum is handled separately via script/UpgradeWormholeBridgeAdapterEthereum.s.sol
///         because the Ethereum xWELL deployment is owned by the deployer, not governance.
contract mipx48 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X48";

    struct AdapterSnapshot {
        address owner;
        uint96 gasLimit;
        address xERC20;
        uint256 bufferCap;
        uint256 buffer;
    }

    AdapterSnapshot public moonbeamBefore;
    AdapterSnapshot public baseBefore;
    AdapterSnapshot public optimismBefore;

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
        /// ============ MOONBEAM ============
        vm.selectFork(MOONBEAM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();

            require(
                impl != address(0),
                "MIP-X48: failed to deploy on Moonbeam"
            );
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3", impl);
        }

        /// ============ BASE ============
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();

            require(impl != address(0), "MIP-X48: failed to deploy on Base");
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3", impl);
        }

        /// ============ OPTIMISM ============
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();

            require(
                impl != address(0),
                "MIP-X48: failed to deploy on Optimism"
            );
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3", impl);
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        /// ============ MOONBEAM ============
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address,address,address,address,uint16)",
                    addresses.getAddress("WORMHOLE_CORE"),
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    address(0), /// no quoter router on Moonbeam
                    address(0), /// no quoter on Moonbeam
                    MOONBEAM_WORMHOLE_CHAIN_ID
                )
            ),
            "Upgrade WormholeBridgeAdapter on Moonbeam to Executor framework"
        );

        /// ============ BASE ============
        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address,address,address,address,uint16)",
                    addresses.getAddress("WORMHOLE_CORE"),
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
                    addresses.getAddress("WORMHOLE_QUOTER"),
                    BASE_WORMHOLE_CHAIN_ID
                )
            ),
            "Upgrade WormholeBridgeAdapter on Base to Executor framework"
        );

        /// ============ OPTIMISM ============
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"),
                abi.encodeWithSignature(
                    "initializeV3(address,address,address,address,uint16)",
                    addresses.getAddress("WORMHOLE_CORE"),
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
                    addresses.getAddress("WORMHOLE_QUOTER"),
                    OPTIMISM_WORMHOLE_CHAIN_ID
                )
            ),
            "Upgrade WormholeBridgeAdapter on Optimism to Executor framework"
        );

        vm.selectFork(primaryForkId());
    }

    function beforeSimulationHook(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);
        moonbeamBefore = _snapshotAdapter(addresses);

        vm.selectFork(BASE_FORK_ID);
        baseBefore = _snapshotAdapter(addresses);

        vm.selectFork(OPTIMISM_FORK_ID);
        optimismBefore = _snapshotAdapter(addresses);

        vm.selectFork(primaryForkId());
    }

    function _snapshotAdapter(
        Addresses addresses
    ) internal view returns (AdapterSnapshot memory) {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);
        xWELL xwell = xWELL(addresses.getAddress("xWELL_PROXY"));

        return
            AdapterSnapshot({
                owner: adapter.owner(),
                gasLimit: adapter.gasLimit(),
                xERC20: address(adapter.xERC20()),
                bufferCap: xwell.bufferCap(proxy),
                buffer: xwell.buffer(proxy)
            });
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);
        _validateChainUpgrade(
            addresses,
            "MOONBEAM_PROXY_ADMIN",
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            MOONBEAM_WORMHOLE_CHAIN_ID,
            moonbeamBefore,
            "Moonbeam"
        );

        vm.selectFork(BASE_FORK_ID);
        _validateChainUpgrade(
            addresses,
            "MRD_PROXY_ADMIN",
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            BASE_WORMHOLE_CHAIN_ID,
            baseBefore,
            "Base"
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChainUpgrade(
            addresses,
            "MRD_PROXY_ADMIN",
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            OPTIMISM_WORMHOLE_CHAIN_ID,
            optimismBefore,
            "Optimism"
        );

        vm.selectFork(primaryForkId());
    }

    function _validateChainUpgrade(
        Addresses addresses,
        string memory proxyAdminName,
        address expectedExecutor,
        uint16 expectedWormholeChainId,
        AdapterSnapshot memory before,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address proxyAdmin = addresses.getAddress(proxyAdminName);
        address expectedImpl = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_IMPL_V3"
        );
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);

        /// 1. Verify implementation upgraded
        assertEq(
            _getProxyImplementation(proxyAdmin, proxy),
            expectedImpl,
            string.concat(chainName, ": implementation not upgraded")
        );

        /// 2. Verify initializeV3 state was set
        assertEq(
            address(adapter.coreBridge()),
            addresses.getAddress("WORMHOLE_CORE"),
            string.concat(chainName, ": coreBridge not set correctly")
        );
        assertEq(
            address(adapter.executor()),
            expectedExecutor,
            string.concat(chainName, ": executor not set correctly")
        );
        assertEq(
            adapter.wormholeChainId(),
            expectedWormholeChainId,
            string.concat(chainName, ": wormholeChainId not set correctly")
        );

        /// 3. Verify backwards-compat getter
        assertEq(
            address(adapter.wormholeRelayer()),
            addresses.getAddress("WORMHOLE_CORE"),
            string.concat(
                chainName,
                ": wormholeRelayer should return coreBridge"
            )
        );

        /// 4. Verify storage preservation
        assertEq(
            adapter.owner(),
            before.owner,
            string.concat(chainName, ": owner changed after upgrade")
        );
        assertEq(
            adapter.gasLimit(),
            before.gasLimit,
            string.concat(chainName, ": gasLimit changed after upgrade")
        );
        assertEq(
            address(adapter.xERC20()),
            before.xERC20,
            string.concat(chainName, ": xERC20 changed after upgrade")
        );

        xWELL xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        assertEq(
            xwell.bufferCap(proxy),
            before.bufferCap,
            string.concat(chainName, ": bufferCap changed after upgrade")
        );

        /// 5. Verify trusted senders still configured for all peer chains
        uint16[3] memory allChainIds = [
            MOONBEAM_WORMHOLE_CHAIN_ID,
            BASE_WORMHOLE_CHAIN_ID,
            OPTIMISM_WORMHOLE_CHAIN_ID
        ];
        for (uint256 i = 0; i < allChainIds.length; i++) {
            if (allChainIds[i] == expectedWormholeChainId) continue;
            assertTrue(
                adapter.isTrustedSender(allChainIds[i], address(adapter)),
                string.concat(
                    chainName,
                    ": peer not trusted sender after upgrade"
                )
            );
        }

        /// 6. Verify target addresses still configured for all peer chains
        for (uint256 i = 0; i < allChainIds.length; i++) {
            if (allChainIds[i] == expectedWormholeChainId) continue;
            assertEq(
                adapter.targetAddress(allChainIds[i]),
                address(adapter),
                string.concat(chainName, ": target address not preserved")
            );
        }

        /// 7. Verify initializeV3 cannot be called again
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV3(
            address(1),
            address(1),
            address(0),
            address(0),
            expectedWormholeChainId
        );

        /// 8. Verify initialize cannot be called again
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initialize(
            address(1),
            address(1),
            address(1),
            new uint16[](0),
            new address[](0)
        );

        /// 9. Verify deprecated receiveWormholeMessages always reverts
        vm.expectRevert("WormholeBridge: deprecated, use executeVAAv1");
        adapter.receiveWormholeMessages(
            "",
            new bytes[](0),
            bytes32(0),
            0,
            bytes32(0)
        );
    }

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

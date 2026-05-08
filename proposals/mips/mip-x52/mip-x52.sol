//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";
import {IExecutorQuoterRouter} from "@protocol/wormhole/IExecutorQuoterRouter.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X52: Upgrade xWELL WormholeBridgeAdapter to Executor framework
/// @notice Upgrades WormholeBridgeAdapter on Moonbeam, Base, and Optimism
///         to V5 with the Wormhole Executor framework, replacing processVAA
///         with executeVAAv1 and adding on-chain/off-chain quote support.
contract mipx52 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X52";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x52/x52.md")
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
        /// Deploy V5 implementations per chain
        /// -------------------------------------------------------

        /// Moonbeam: WormholeUnwrapperAdapter (unwrap xWELL → WELL via lockbox)
        vm.selectFork(primaryForkId());
        if (!addresses.isAddressSet("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V5")) {
            vm.startBroadcast();
            address impl = address(new WormholeUnwrapperAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V5", impl);
        }

        /// Base: WormholeBridgeAdapter
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5", impl);
        }

        /// Optimism: WormholeBridgeAdapter
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5", impl);
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        /// -------------------------------------------------------
        /// Moonbeam: upgradeAndCall with initializeV5
        /// No on-chain quoter on Moonbeam (executorQuoterRouter = address(0))
        /// -------------------------------------------------------

        vm.selectFork(primaryForkId());
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V5"),
                abi.encodeWithSignature(
                    "initializeV5(address,address,address)",
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    address(0), // no on-chain quoter on Moonbeam
                    address(0) // no quoter on Moonbeam
                )
            ),
            "Upgrade WormholeUnwrapperAdapter on Moonbeam to V5 (Executor)"
        );

        /// Re-set the lockbox after upgrading to V5.
        /// The V5 storage variables (executorQuoterRouter, quoterAddress,
        /// executor) shift the child's lockbox slot, so
        /// it reads as zero after the upgrade and needs to be re-initialized.
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setLockbox(address)",
                addresses.getAddress("xWELL_LOCKBOX")
            ),
            "Re-set lockbox on Moonbeam unwrapper (storage shifted by V5)"
        );

        /// -------------------------------------------------------
        /// Base: upgradeAndCall with initializeV5
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5"),
                abi.encodeWithSignature(
                    "initializeV5(address,address,address)",
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
                    addresses.getAddress("WORMHOLE_QUOTER")
                )
            ),
            "Upgrade WormholeBridgeAdapter on Base to V5 (Executor)"
        );

        /// -------------------------------------------------------
        /// Optimism: upgradeAndCall with initializeV5
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgradeAndCall(address,address,bytes)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V5"),
                abi.encodeWithSignature(
                    "initializeV5(address,address,address)",
                    addresses.getAddress("WORMHOLE_EXECUTOR"),
                    addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
                    addresses.getAddress("WORMHOLE_QUOTER")
                )
            ),
            "Upgrade WormholeBridgeAdapter on Optimism to V5 (Executor)"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(primaryForkId());
        _validateAdapter(addresses, "Moonbeam");
        _validateMoonbeamUnwrapper(addresses);

        vm.selectFork(BASE_FORK_ID);
        _validateAdapter(addresses, "Base");
        _validateQuoterSet(addresses, "Base");

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateAdapter(addresses, "Optimism");
        _validateQuoterSet(addresses, "Optimism");

        vm.selectFork(primaryForkId());
    }

    /// @notice Validate adapter state common to all chains
    function _validateAdapter(
        Addresses addresses,
        string memory chainName
    ) internal {
        address proxy = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        address expectedImpl;
        if (block.chainid == MOONBEAM_CHAIN_ID) {
            expectedImpl = addresses.getAddress(
                "WORMHOLE_UNWRAPPER_ADAPTER_IMPL_V5"
            );
        } else {
            expectedImpl = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_IMPL_V5"
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
            string.concat(chainName, ": adapter not upgraded to V5")
        );

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(proxy);

        /// V3 state preserved
        assertEq(
            adapter.CONSISTENCY_LEVEL(),
            1,
            string.concat(chainName, ": CONSISTENCY_LEVEL should be 1")
        );
        assertTrue(
            address(adapter.wormhole()) != address(0),
            string.concat(chainName, ": wormhole core not set")
        );
        assertTrue(
            address(adapter.xERC20()) != address(0),
            string.concat(chainName, ": xERC20 not set")
        );
        assertEq(
            adapter.gasLimit(),
            300_000,
            string.concat(chainName, ": gasLimit changed")
        );

        /// V5 executor state
        assertTrue(
            address(adapter.executor()) != address(0),
            string.concat(chainName, ": executor not set")
        );
        assertEq(
            address(adapter.executor()),
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            string.concat(chainName, ": executor address mismatch")
        );
        /// initializeV5 cannot be called again
        vm.expectRevert("Initializable: contract is already initialized");
        adapter.initializeV5(address(1), address(2), address(3));
    }

    /// @notice Validate Moonbeam-specific unwrapper state
    function _validateMoonbeamUnwrapper(Addresses addresses) internal view {
        WormholeUnwrapperAdapter unwrapper = WormholeUnwrapperAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        assertEq(
            unwrapper.lockbox(),
            addresses.getAddress("xWELL_LOCKBOX"),
            "Moonbeam: lockbox not preserved after V5 upgrade"
        );

        /// Moonbeam has no on-chain quoter
        assertEq(
            address(unwrapper.executorQuoterRouter()),
            address(0),
            "Moonbeam: executorQuoterRouter should be zero"
        );
        assertEq(
            unwrapper.bridgeCost(0),
            0,
            "Moonbeam: bridgeCost should be 0 (no quoter)"
        );
    }

    /// @notice Validate that on-chain quoter is set (Base, Optimism)
    function _validateQuoterSet(
        Addresses addresses,
        string memory chainName
    ) internal view {
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        assertEq(
            address(adapter.executorQuoterRouter()),
            addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
            string.concat(chainName, ": executorQuoterRouter not set")
        );
        assertEq(
            adapter.quoterAddress(),
            addresses.getAddress("WORMHOLE_QUOTER"),
            string.concat(chainName, ": quoterAddress not set")
        );
    }
}

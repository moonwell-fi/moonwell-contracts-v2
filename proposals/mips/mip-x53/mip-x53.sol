//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ITransparentUpgradeableProxy} from "@openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";

/// @title MIP-X53: Fix WormholeBridgeAdapter quoterAddress on Base + Optimism
/// @notice Upgrades the WormholeBridgeAdapter on Base and Optimism to a fresh
///         V6 implementation, then calls `setQuoterAddress` to point the
///         on-chain quoter at the off-chain quoter operator's signer EOA
///         (`WORMHOLE_QUOTER_SIGNER`) and `setGasLimit` to bump the executor
///         gas limit to 700k.
contract mipx53 is HybridProposal {
    using ProposalActions for *;
    using ChainIds for uint256;

    string public constant override name = "MIP-X53";

    /// @notice destination chain used for the validation bridge() call.
    /// On Base we bridge to OP; on OP we bridge to Base.
    uint16 internal constant _BASE_DST_WH_ID = OPTIMISM_WORMHOLE_CHAIN_ID;
    uint16 internal constant _OP_DST_WH_ID = BASE_WORMHOLE_CHAIN_ID;

    /// @notice mocked-user bridge amount used in `validate()`
    uint256 internal constant BRIDGE_AMOUNT = 1e18;

    uint96 internal constant NEW_GAS_LIMIT = 700_000;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x53/x53.md")
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

    /// @notice Deploy a fresh V6 implementation on Base and Optimism. Same
    ///         logic as V5 plus the new `setQuoterAddress` setter.
    function deploy(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6", impl);
        }

        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6")) {
            vm.startBroadcast();
            address impl = address(new WormholeBridgeAdapter());
            vm.stopBroadcast();
            addresses.addAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6", impl);
        }

        vm.selectFork(primaryForkId());
    }

    function build(Addresses addresses) public override {
        /// -------------------------------------------------------
        /// Moonbeam: setGasLimit
        /// -------------------------------------------------------

        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("setGasLimit(uint96)", NEW_GAS_LIMIT),
            "Bump executor gas limit on Moonbeam WormholeBridgeAdapter to 700k"
        );

        /// -------------------------------------------------------
        /// Base: upgrade impl, then setQuoterAddress + setGasLimit
        /// -------------------------------------------------------

        vm.selectFork(BASE_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6")
            ),
            "Upgrade WormholeBridgeAdapter on Base to V6 impl"
        );
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setQuoterAddress(address)",
                addresses.getAddress("WORMHOLE_QUOTER_SIGNER")
            ),
            "Set quoter signer EOA on Base WormholeBridgeAdapter"
        );
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("setGasLimit(uint96)", NEW_GAS_LIMIT),
            "Bump executor gas limit on Base WormholeBridgeAdapter to 700k"
        );

        /// -------------------------------------------------------
        /// Optimism: upgrade impl, then setQuoterAddress + setGasLimit
        /// -------------------------------------------------------

        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6")
            ),
            "Upgrade WormholeBridgeAdapter on Optimism to V6 impl"
        );
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setQuoterAddress(address)",
                addresses.getAddress("WORMHOLE_QUOTER_SIGNER")
            ),
            "Set quoter signer EOA on Optimism WormholeBridgeAdapter"
        );
        _pushAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("setGasLimit(uint96)", NEW_GAS_LIMIT),
            "Bump executor gas limit on Optimism WormholeBridgeAdapter to 700k"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        // Moonbeam
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        assertEq(
            adapter.gasLimit(),
            NEW_GAS_LIMIT,
            "Moonbeam: gasLimit not bumped to 700k"
        );

        vm.selectFork(BASE_FORK_ID);
        _validateAdapterV6(addresses, "Base", _BASE_DST_WH_ID);

        vm.selectFork(OPTIMISM_FORK_ID);
        _validateAdapterV6(addresses, "Optimism", _OP_DST_WH_ID);

        vm.selectFork(primaryForkId());
    }

    /// @notice Per-chain validation: storage state, bridgeCost > 0, and a
    ///         mocked-user bridge() call that hits the live executor router.
    function _validateAdapterV6(
        Addresses addresses,
        string memory chainName,
        uint16 dstWormholeId
    ) internal {
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// 1. Implementation upgraded
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");
        address actualImpl = ProxyAdmin(proxyAdmin).getProxyImplementation(
            ITransparentUpgradeableProxy(address(adapter))
        );
        assertEq(
            actualImpl,
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_IMPL_V6"),
            string.concat(chainName, ": adapter not upgraded to V6")
        );

        /// 2. quoterAddress storage now points at the signer EOA
        assertEq(
            adapter.quoterAddress(),
            addresses.getAddress("WORMHOLE_QUOTER_SIGNER"),
            string.concat(chainName, ": quoterAddress not set to signer")
        );

        /// 3. V5 state preserved (router, executor, wormhole, gas limit)
        assertEq(
            address(adapter.executorQuoterRouter()),
            addresses.getAddress("WORMHOLE_QUOTER_ROUTER"),
            string.concat(chainName, ": executorQuoterRouter changed")
        );
        assertEq(
            address(adapter.executor()),
            addresses.getAddress("WORMHOLE_EXECUTOR"),
            string.concat(chainName, ": executor changed")
        );
        assertTrue(
            address(adapter.wormhole()) != address(0),
            string.concat(chainName, ": wormhole core not set")
        );
        assertEq(
            adapter.gasLimit(),
            NEW_GAS_LIMIT,
            string.concat(chainName, ": gasLimit not bumped to 700k")
        );

        /// 4. bridgeCost(dst) returns a real positive quote now
        uint256 cost = adapter.bridgeCost(dstWormholeId);
        assertGt(
            cost,
            0,
            string.concat(chainName, ": bridgeCost returned 0 after V6 fix")
        );

        /// 5. Mocked-user bridge: end-to-end against the live executor router.
        ///    Pattern mirrors test/integration/xWELL/WormholeBridgeAdapterIntegration.t.sol#testBridgeOutAfterUpgrade.
        _runMockedUserBridge(
            addresses,
            adapter,
            chainName,
            dstWormholeId,
            cost
        );
    }

    /// @notice Funds a synthetic user with xWELL + ETH and exercises the
    ///         on-chain-quote bridge() overload. After the V6 fix this must
    ///         not revert; tokens must burn and totalSupply must drop.
    function _runMockedUserBridge(
        Addresses addresses,
        WormholeBridgeAdapter adapter,
        string memory chainName,
        uint16 dstWormholeId,
        uint256 cost
    ) internal {
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
            uint256(dstWormholeId),
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

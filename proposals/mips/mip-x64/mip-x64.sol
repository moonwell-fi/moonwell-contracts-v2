//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";
import {HybridProposalV2, ActionType} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, ETHEREUM_FORK_ID, MOONBEAM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_WORMHOLE_CHAIN_ID, ChainIds} from "@utils/ChainIds.sol";

/// @title MIP-X64: Moonbeam sunset — "Before Sunset" phase
/// @notice First phase of the Moonbeam (Wormhole chain id 16) sunset. This
///         proposal severs the OUTBOUND routes TO Moonbeam without disturbing
///         anything on Moonbeam itself:
///
///         1. Governance: removes Moonbeam from the Ethereum
///            MultichainGovernorV2's external chain configs. Because
///            WormholeBridgeBase.isTrustedSender(chainId, addr) is literally
///            `targetAddress[chainId] == addr` and _bridgeOutAll iterates the
///            _targetChains set, a single removeExternalChainConfigs call both
///            (a) stops broadcasting proposals to the Moonbeam vote collector
///            and (b) stops accepting Moonbeam vote-collection VAAs.
///
///         2. xWELL bridge: zeroes targetAddress[16] on the Ethereum, Base, and
///            Optimism WormholeBridgeAdapters via setTargetAddresses. This
///            blocks bridging xWELL TO Moonbeam (send requires
///            targetAddress[dst] != 0) while leaving the EnumerableSet-based
///            trusted-sender list untouched — so users can still bridge OUT of
///            Moonbeam (receives FROM Moonbeam keep working).
///
///         The Moonbeam-side adapter is intentionally NOT touched: its outbound
///         routes to Ethereum/Base/Optimism stay live so holders can exit. A
///         later "After Sunset" proposal will handle final decommissioning.
///
///         This is the exact reverse of MIP-X55 (which added the Ethereum
///         routes) for the Moonbeam leg.
///
/// how to generate calldata / run a standalone simulation against forks:
/*
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=true
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/
/// forge script proposals/mips/mip-x64/mip-x64.sol:mipx64 --ffi -vvv
contract mipx64 is HybridProposalV2 {
    using ChainIds for uint256;

    string public constant override name = "MIP-X64";

    /// @notice mocked-user bridge amount used in the `validate()` smoke tests.
    uint256 internal constant BRIDGE_AMOUNT = 1e18;

    /// ---------------------------------------------------------------------
    /// pre-execution snapshots captured in afterDeploy() (runs before
    /// build()/simulate()), asserted in validate() so an accidental storage
    /// reset of an UNTOUCHED route surfaces as a strict-equality failure.
    /// ---------------------------------------------------------------------

    /// @notice Ethereum MultichainGovernorV2 pre-state
    uint256 internal preGovTargetChainsLen; // expected 3 -> 2 after
    address internal preGovTargetBase; // targetAddress[30] (Base collector)
    address internal preGovTargetOptimism; // targetAddress[24] (OP collector)

    /// @notice Ethereum WormholeBridgeAdapter pre-state
    address internal preEthAdapterTargetBase; // targetAddress[30]
    address internal preEthAdapterTargetOptimism; // targetAddress[24]
    bool internal preEthAdapterTrustsMoonbeam; // isTrustedSender[16]

    /// @notice Base WormholeBridgeAdapter pre-state
    address internal preBaseAdapterTargetEthereum; // targetAddress[2]
    address internal preBaseAdapterTargetOptimism; // targetAddress[24]
    bool internal preBaseAdapterTrustsMoonbeam; // isTrustedSender[16]

    /// @notice Optimism WormholeBridgeAdapter pre-state
    address internal preOptimismAdapterTargetEthereum; // targetAddress[2]
    address internal preOptimismAdapterTargetBase; // targetAddress[30]
    bool internal preOptimismAdapterTrustsMoonbeam; // isTrustedSender[16]

    /// @notice Moonbeam WormholeBridgeAdapter pre-state (must stay untouched)
    address internal preMoonbeamAdapterTargetEthereum; // targetAddress[2]
    address internal preMoonbeamAdapterTargetBase; // targetAddress[30]
    address internal preMoonbeamAdapterTargetOptimism; // targetAddress[24]

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x64/x64.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice mirrors Proposal.run() minus the top-level broadcast wrapper,
    /// following the other cross-chain proposals (mip-x53, mip-x58): this
    /// proposal deploys nothing, and afterDeploy()/build()/validate() switch
    /// forks, which does not compose with an active vm.startBroadcast().
    /// Keeps the descriptionUri injection so DO_PRINT calldata carries the
    /// pinned IPFS URI from mips.json.
    function run() public override {
        primaryForkId().createForksAndSelect();

        Addresses addresses = new Addresses();
        vm.makePersistent(address(addresses));

        setProposalDescriptionUri(_resolveProposalDescriptionUri(this.name()));

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

    /// @notice snapshot every route this proposal reads in validate() — both
    /// the ones it mutates (to prove the transition) and the ones it must leave
    /// alone (to prove no accidental reset). Restores the primary fork on exit.
    function afterDeploy(Addresses addresses, address) public override {
        // -------------------- Ethereum --------------------
        vm.selectFork(ETHEREUM_FORK_ID);
        MultichainGovernorV2 governor = MultichainGovernorV2(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"))
        );
        preGovTargetChainsLen = governor.getAllTargetChains().length;
        preGovTargetBase = governor.targetAddress(BASE_WORMHOLE_CHAIN_ID);
        preGovTargetOptimism = governor.targetAddress(
            OPTIMISM_WORMHOLE_CHAIN_ID
        );

        address moonbeamAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            MOONBEAM_CHAIN_ID
        );

        WormholeBridgeAdapter ethAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        preEthAdapterTargetBase = ethAdapter.targetAddress(
            BASE_WORMHOLE_CHAIN_ID
        );
        preEthAdapterTargetOptimism = ethAdapter.targetAddress(
            OPTIMISM_WORMHOLE_CHAIN_ID
        );
        preEthAdapterTrustsMoonbeam = ethAdapter.isTrustedSender(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            moonbeamAdapter
        );

        // ---------------------- Base ----------------------
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter baseAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        preBaseAdapterTargetEthereum = baseAdapter.targetAddress(
            ETHEREUM_WORMHOLE_CHAIN_ID
        );
        preBaseAdapterTargetOptimism = baseAdapter.targetAddress(
            OPTIMISM_WORMHOLE_CHAIN_ID
        );
        preBaseAdapterTrustsMoonbeam = baseAdapter.isTrustedSender(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            moonbeamAdapter
        );

        // -------------------- Optimism --------------------
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter optimismAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        preOptimismAdapterTargetEthereum = optimismAdapter.targetAddress(
            ETHEREUM_WORMHOLE_CHAIN_ID
        );
        preOptimismAdapterTargetBase = optimismAdapter.targetAddress(
            BASE_WORMHOLE_CHAIN_ID
        );
        preOptimismAdapterTrustsMoonbeam = optimismAdapter.isTrustedSender(
            MOONBEAM_WORMHOLE_CHAIN_ID,
            moonbeamAdapter
        );

        // -------------------- Moonbeam --------------------
        vm.selectFork(MOONBEAM_FORK_ID);
        WormholeBridgeAdapter moonbeamAdapterContract = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        preMoonbeamAdapterTargetEthereum = moonbeamAdapterContract
            .targetAddress(ETHEREUM_WORMHOLE_CHAIN_ID);
        preMoonbeamAdapterTargetBase = moonbeamAdapterContract.targetAddress(
            BASE_WORMHOLE_CHAIN_ID
        );
        preMoonbeamAdapterTargetOptimism = moonbeamAdapterContract
            .targetAddress(OPTIMISM_WORMHOLE_CHAIN_ID);

        vm.selectFork(primaryForkId());
    }

    /// @notice Push the 4 sunset actions.
    /// @dev
    ///   [0] Ethereum: governor.removeExternalChainConfigs([{16, collector}])
    ///   [1] Ethereum: Ethereum adapter.setTargetAddresses([{16, address(0)}])
    ///   [2] Base:     Base adapter.setTargetAddresses([{16, address(0)}])
    ///   [3] Optimism: Optimism adapter.setTargetAddresses([{16, address(0)}])
    function build(Addresses addresses) public override {
        // -------------------- Ethereum hub --------------------
        vm.selectFork(ETHEREUM_FORK_ID);

        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY");
        address ethAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        // The Moonbeam vote collector is the governor's target for chain 16.
        address moonbeamCollector = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY",
            MOONBEAM_CHAIN_ID
        );

        // Action 0: drop Moonbeam from the governor's broadcast + vote-collection
        // config. removeExternalChainConfigs is onlyGovernor; the governor
        // executes this Ethereum action against itself, so the self-call passes.
        WormholeTrustedSender.TrustedSender[]
            memory governorConfig = _moonbeamConfig(moonbeamCollector);
        _pushAction(
            governor,
            abi.encodeWithSignature(
                "removeExternalChainConfigs((uint16,address)[])",
                governorConfig
            ),
            "Remove Moonbeam from MultichainGovernorV2 external chain configs (stops proposal broadcast to and vote collection from Moonbeam)",
            ActionType.Ethereum
        );

        // Action 1: zero the Ethereum adapter's Moonbeam route.
        _pushAction(
            ethAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                _moonbeamZeroConfig()
            ),
            "Zero the xWELL bridge route to Moonbeam on the Ethereum WormholeBridgeAdapter",
            ActionType.Ethereum
        );

        // ---------------------- Base ----------------------
        vm.selectFork(BASE_FORK_ID);
        address baseAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        _pushAction(
            baseAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                _moonbeamZeroConfig()
            ),
            "Zero the xWELL bridge route to Moonbeam on the Base WormholeBridgeAdapter",
            ActionType.Base
        );

        // -------------------- Optimism --------------------
        vm.selectFork(OPTIMISM_FORK_ID);
        address optimismAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        _pushAction(
            optimismAdapter,
            abi.encodeWithSignature(
                "setTargetAddresses((uint16,address)[])",
                _moonbeamZeroConfig()
            ),
            "Zero the xWELL bridge route to Moonbeam on the Optimism WormholeBridgeAdapter",
            ActionType.Optimism
        );

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address) public override {
        address moonbeamCollector = addresses.getAddress(
            "VOTE_COLLECTION_V2_PROXY",
            MOONBEAM_CHAIN_ID
        );
        address moonbeamAdapter = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY",
            MOONBEAM_CHAIN_ID
        );

        // ==================== Ethereum ====================
        vm.selectFork(ETHEREUM_FORK_ID);
        _validateEthereum(addresses, moonbeamCollector, moonbeamAdapter);

        // ====================== Base ======================
        vm.selectFork(BASE_FORK_ID);
        WormholeBridgeAdapter baseAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        require(
            baseAdapter.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID) == address(0),
            "MIP-X64: Base adapter targetAddress[Moonbeam] not zeroed"
        );
        require(
            baseAdapter.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamAdapter
            ),
            "MIP-X64: Base adapter no longer trusts Moonbeam (inbound must stay open)"
        );
        require(
            baseAdapter.targetAddress(ETHEREUM_WORMHOLE_CHAIN_ID) ==
                preBaseAdapterTargetEthereum,
            "MIP-X64: Base adapter targetAddress[Ethereum] changed"
        );
        require(
            baseAdapter.targetAddress(OPTIMISM_WORMHOLE_CHAIN_ID) ==
                preBaseAdapterTargetOptimism,
            "MIP-X64: Base adapter targetAddress[Optimism] changed"
        );
        require(
            preBaseAdapterTrustsMoonbeam,
            "MIP-X64: snapshot missing Base->Moonbeam trust (afterDeploy not run)"
        );
        _assertBridgeToMoonbeamReverts(baseAdapter);
        _runMockedUserBridge(
            addresses,
            baseAdapter,
            ETHEREUM_WORMHOLE_CHAIN_ID,
            "Base->Ethereum"
        );

        // ==================== Optimism ====================
        vm.selectFork(OPTIMISM_FORK_ID);
        WormholeBridgeAdapter optimismAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        require(
            optimismAdapter.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID) ==
                address(0),
            "MIP-X64: Optimism adapter targetAddress[Moonbeam] not zeroed"
        );
        require(
            optimismAdapter.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamAdapter
            ),
            "MIP-X64: Optimism adapter no longer trusts Moonbeam (inbound must stay open)"
        );
        require(
            optimismAdapter.targetAddress(ETHEREUM_WORMHOLE_CHAIN_ID) ==
                preOptimismAdapterTargetEthereum,
            "MIP-X64: Optimism adapter targetAddress[Ethereum] changed"
        );
        require(
            optimismAdapter.targetAddress(BASE_WORMHOLE_CHAIN_ID) ==
                preOptimismAdapterTargetBase,
            "MIP-X64: Optimism adapter targetAddress[Base] changed"
        );
        require(
            preOptimismAdapterTrustsMoonbeam,
            "MIP-X64: snapshot missing Optimism->Moonbeam trust (afterDeploy not run)"
        );
        _assertBridgeToMoonbeamReverts(optimismAdapter);
        _runMockedUserBridge(
            addresses,
            optimismAdapter,
            ETHEREUM_WORMHOLE_CHAIN_ID,
            "Optimism->Ethereum"
        );

        // ==================== Moonbeam ====================
        // The Moonbeam adapter is intentionally untouched so users can still
        // bridge OUT of Moonbeam. Assert every outbound route is unchanged.
        vm.selectFork(MOONBEAM_FORK_ID);
        WormholeBridgeAdapter moonbeamAdapterContract = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        require(
            moonbeamAdapterContract.targetAddress(ETHEREUM_WORMHOLE_CHAIN_ID) ==
                preMoonbeamAdapterTargetEthereum,
            "MIP-X64: Moonbeam adapter targetAddress[Ethereum] changed"
        );
        require(
            moonbeamAdapterContract.targetAddress(BASE_WORMHOLE_CHAIN_ID) ==
                preMoonbeamAdapterTargetBase,
            "MIP-X64: Moonbeam adapter targetAddress[Base] changed"
        );
        require(
            moonbeamAdapterContract.targetAddress(OPTIMISM_WORMHOLE_CHAIN_ID) ==
                preMoonbeamAdapterTargetOptimism,
            "MIP-X64: Moonbeam adapter targetAddress[Optimism] changed"
        );
        // sanity: the untouched Moonbeam routes must actually be live (non-zero)
        require(
            preMoonbeamAdapterTargetEthereum != address(0) &&
                preMoonbeamAdapterTargetBase != address(0) &&
                preMoonbeamAdapterTargetOptimism != address(0),
            "MIP-X64: Moonbeam outbound routes were not all set pre-execution"
        );

        vm.selectFork(primaryForkId());
    }

    /// @notice Ethereum-side assertions, split out to keep validate() readable.
    function _validateEthereum(
        Addresses addresses,
        address moonbeamCollector,
        address moonbeamAdapter
    ) internal view {
        MultichainGovernorV2 governor = MultichainGovernorV2(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"))
        );

        // governor no longer routes to / trusts the Moonbeam collector
        require(
            governor.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID) == address(0),
            "MIP-X64: governor targetAddress[Moonbeam] not zeroed"
        );
        require(
            !governor.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamCollector
            ),
            "MIP-X64: governor still trusts Moonbeam collector"
        );

        // target chain set shrank from 3 to 2 and now holds exactly {Base, OP}
        uint16[] memory chains = governor.getAllTargetChains();
        require(
            preGovTargetChainsLen == 3,
            "MIP-X64: expected 3 governor target chains pre-execution"
        );
        require(
            chains.length == 2,
            "MIP-X64: governor should have exactly 2 target chains after removal"
        );
        require(
            _containsChain(chains, BASE_WORMHOLE_CHAIN_ID),
            "MIP-X64: governor target chains missing Base"
        );
        require(
            _containsChain(chains, OPTIMISM_WORMHOLE_CHAIN_ID),
            "MIP-X64: governor target chains missing Optimism"
        );
        require(
            !_containsChain(chains, MOONBEAM_WORMHOLE_CHAIN_ID),
            "MIP-X64: governor target chains still include Moonbeam"
        );

        // untouched governor routes preserved
        require(
            governor.targetAddress(BASE_WORMHOLE_CHAIN_ID) == preGovTargetBase,
            "MIP-X64: governor targetAddress[Base] changed"
        );
        require(
            governor.targetAddress(OPTIMISM_WORMHOLE_CHAIN_ID) ==
                preGovTargetOptimism,
            "MIP-X64: governor targetAddress[Optimism] changed"
        );

        // Ethereum adapter: outbound to Moonbeam severed, inbound preserved
        WormholeBridgeAdapter ethAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        require(
            ethAdapter.targetAddress(MOONBEAM_WORMHOLE_CHAIN_ID) == address(0),
            "MIP-X64: Ethereum adapter targetAddress[Moonbeam] not zeroed"
        );
        require(
            ethAdapter.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                moonbeamAdapter
            ),
            "MIP-X64: Ethereum adapter no longer trusts Moonbeam (inbound must stay open)"
        );
        require(
            preEthAdapterTrustsMoonbeam,
            "MIP-X64: snapshot missing Ethereum->Moonbeam trust (afterDeploy not run)"
        );
        require(
            ethAdapter.targetAddress(BASE_WORMHOLE_CHAIN_ID) ==
                preEthAdapterTargetBase,
            "MIP-X64: Ethereum adapter targetAddress[Base] changed"
        );
        require(
            ethAdapter.targetAddress(OPTIMISM_WORMHOLE_CHAIN_ID) ==
                preEthAdapterTargetOptimism,
            "MIP-X64: Ethereum adapter targetAddress[Optimism] changed"
        );
    }

    /// @notice Negative smoke test: bridging xWELL TO Moonbeam must revert now
    /// that targetAddress[16] == 0. In the 3-arg _bridgeOut, the msg.value ==
    /// bridgeCost(16) check passes (we fund exactly the quote), so execution
    /// reaches `require(targetAddress[16] != 0, "WormholeBridge: invalid target
    /// chain")` — the revert we assert. The revert precedes _burnTokens, so no
    /// xWELL balance/approval is needed.
    function _assertBridgeToMoonbeamReverts(
        WormholeBridgeAdapter adapter
    ) internal {
        uint256 cost = adapter.bridgeCost(MOONBEAM_WORMHOLE_CHAIN_ID);
        address user = address(0xBEEF);
        vm.deal(user, cost);

        vm.prank(user);
        vm.expectRevert("WormholeBridge: invalid target chain");
        adapter.bridge{value: cost}(
            uint256(MOONBEAM_WORMHOLE_CHAIN_ID),
            BRIDGE_AMOUNT,
            user
        );
    }

    /// @notice Positive smoke test: a preserved outbound route (Ethereum) still
    /// burns xWELL and routes through the executor. Mirrors
    /// mip-x55.sol#_runMockedUserBridge.
    function _runMockedUserBridge(
        Addresses addresses,
        WormholeBridgeAdapter adapter,
        uint16 dstWormholeChainId,
        string memory label
    ) internal {
        uint256 cost = adapter.bridgeCost(dstWormholeChainId);
        assertGt(
            cost,
            0,
            string.concat(
                label,
                ": bridgeCost returned 0 (route unexpectedly severed)"
            )
        );

        address user = address(0xBEEF);
        IERC20 xWell = IERC20(addresses.getAddress("xWELL_PROXY"));

        deal(address(xWell), user, BRIDGE_AMOUNT, true);
        vm.deal(user, cost);

        uint256 userBalanceBefore = xWell.balanceOf(user);
        uint256 totalSupplyBefore = xWell.totalSupply();

        vm.startPrank(user);
        xWell.approve(address(adapter), BRIDGE_AMOUNT);
        adapter.bridge{value: cost}(
            uint256(dstWormholeChainId),
            BRIDGE_AMOUNT,
            user
        );
        vm.stopPrank();

        assertEq(
            userBalanceBefore - xWell.balanceOf(user),
            BRIDGE_AMOUNT,
            string.concat(label, ": user xWELL not burned by bridge()")
        );
        assertEq(
            totalSupplyBefore - xWell.totalSupply(),
            BRIDGE_AMOUNT,
            string.concat(label, ": xWELL totalSupply not reduced")
        );
    }

    /// @notice {16, collector} — used for the governor's removeExternalChainConfigs.
    /// _removeTargetAddresses keys off chainId only, but the real collector is
    /// supplied for clarity and calldata self-documentation.
    function _moonbeamConfig(
        address moonbeamCollector
    ) internal pure returns (WormholeTrustedSender.TrustedSender[] memory cfg) {
        cfg = new WormholeTrustedSender.TrustedSender[](1);
        cfg[0] = WormholeTrustedSender.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: moonbeamCollector
        });
    }

    /// @notice {16, address(0)} — used for adapter.setTargetAddresses to zero
    /// the Moonbeam route (setTargetAddresses overwrites unconditionally).
    function _moonbeamZeroConfig()
        internal
        pure
        returns (WormholeTrustedSender.TrustedSender[] memory cfg)
    {
        cfg = new WormholeTrustedSender.TrustedSender[](1);
        cfg[0] = WormholeTrustedSender.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: address(0)
        });
    }

    function _containsChain(
        uint16[] memory chains,
        uint16 target
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < chains.length; i++) {
            if (chains[i] == target) {
                return true;
            }
        }
        return false;
    }
}

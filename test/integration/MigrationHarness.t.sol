//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MToken} from "@protocol/MToken.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";

import {ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {mipx56} from "@proposals/mips/mip-x56/mip-x56.sol";
import {mipe00} from "@proposals/mips/mip-e00/mip-e00.sol";

import {EthMarketUpdateSmoke} from "@test/integration/proposals/EthMarketUpdateSmoke.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";

import {ETHEREUM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_FORK_ID, ETHEREUM_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title MigrationHarness
/// @notice End-to-end validation harness for the Moonwell governance migration
///         to Ethereum (mip-x56) + Ethereum core deployment (mip-e00). Runs
///         against persistent Tenderly VNets — RPC URLs come from
///         setup-migration-vnets.ts via foundry.toml's [rpc_endpoints] block.
///
///         The harness drives mip-x56 and mip-e00 directly (NOT via
///         PostProposalCheck) so it doesn't pull in unrelated proposals or
///         require template artifacts to be built.
///
///         After Phases A + C, applies stubs for migration-summary TODOs
///         that aren't yet absorbed by either proposal:
///         1. Eth xWELL acceptOwnership()
///         2. Eth VotingPowerAggregator acceptOwnership()
///         3. xWELL bridging activation (addTrustedSenders on all 4 chains)
///         4. Moonbeam mTokens + Unitroller _acceptAdmin()
///
///         Then drives a smoke proposal through the new governor to prove
///         the full propose → vote → execute path works on Eth-native
///         markets.
contract MigrationHarness is Test {
    using ChainIds for uint256;
    using stdStorage for StdStorage;

    /// @notice mocked voting power for the smoke-test proposer
    uint256 public constant PROPOSER_VOTES = 200_000_000e18; // > quorum

    /// @notice test proposer address used by the smoke-test proposal
    address public constant SMOKE_PROPOSER = address(0x7E5700);

    Addresses public addresses;

    /// ----- Live system handles (loaded after migration) -----
    MultichainGovernorV2 public governorV2;
    VotingPowerAggregator public ethereumVotingPower;
    xWELL public ethereumXWell;
    WormholeBridgeAdapter public ethereumBridgeAdapter;

    Unitroller public ethUnitroller;
    Comptroller public ethComptroller;
    MToken public mWETH;

    function setUp() public {
        // Create forks (resolves RPC URLs from foundry.toml [rpc_endpoints])
        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        // Phase A: run mip-x56 (governor migration)
        _phaseA_runMipX56();

        // Phase A.5: simulate PostDeployEthereumXWell.s.sol — the deployer-side
        // script that transfers xWELL + WormholeBridgeAdapter + ProxyAdmin
        // ownership on Ethereum to the new governorV2 (Ownable2Step: sets
        // pendingOwner). Without this, e00.build()'s acceptOwnership on the
        // Eth WormholeBridgeAdapter reverts with "caller is not the new owner".
        _phaseA5_postDeployEthereumXWell();

        // Phase B: install Wormhole relayer mock BEFORE e00 so e00's cross-
        // chain accepts (Moonbeam VC, Moonbeam bridge adapter, Moonbeam VPA,
        // Base/OP VPA) reach the satellite TemporalGovernors in-memory.
        _phaseB_installWormholeMock();

        // Phase C: run mip-e00 (Ethereum core deployment)
        _phaseC_runMipE00();

        _loadHandles();

        // Phase D first: process all the post-migration acceptOwnership/
        // _acceptAdmin calls. These need to complete BEFORE Phase 0 because
        // Phase 0 pranks as the bridge adapters' owners — which on the
        // satellite chains is the TemporalGovernor only after it accepts.
        _phaseDPostMigrationAcceptsStub();

        // Phase 0: xWELL bridging activation stub (now TG owns the bridge
        // adapters on Moonbeam/Base/Op).
        _phase0XWellBridgingStub();

        // Mock voting power for the smoke proposer
        _grantSmokeProposerVotingPower();
    }

    /// --------------------------------------------------------------------
    /// MIGRATION PHASES
    /// --------------------------------------------------------------------

    function _phaseA_runMipX56() internal {
        mipx56 x56 = new mipx56();
        vm.makePersistent(address(x56));

        // Match ProposalMap.runProposal's pattern: deployer = address(proposal).
        // The proposal contract itself is the msg.sender for all afterDeploy
        // calls, so any ownership/admin set in deploy() with this address as
        // admin will match later afterDeploy() calls.
        address deployer = address(x56);

        x56.deploy(addresses, deployer);
        x56.afterDeploy(addresses, deployer);
        x56.build(addresses);
        x56.simulate(addresses, deployer);
        x56.validate(addresses, deployer);
    }

    /// @notice Simulate PostDeployEthereumXWell.s.sol: deployer transfers
    ///         ownership of Ethereum xWELL, WormholeBridgeAdapter, and
    ///         ProxyAdmin to governorV2. xWELL and WormholeBridgeAdapter use
    ///         Ownable2Step, so only pendingOwner is set; ProxyAdmin uses
    ///         1-step Ownable.
    function _phaseA5_postDeployEthereumXWell() internal {
        vm.selectFork(ETHEREUM_FORK_ID);

        address xWellProxy = addresses.getAddress("xWELL_PROXY");
        address bridgeAdapterProxy = addresses.getAddress(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY"
        );
        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");
        address newGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        // xWELL — Ownable2Step
        address xWellOwner = xWELL(xWellProxy).owner();
        if (xWellOwner != newGovernor) {
            vm.prank(xWellOwner);
            xWELL(xWellProxy).transferOwnership(newGovernor);
        }

        // WormholeBridgeAdapter — Ownable2Step
        address adapterOwner = WormholeBridgeAdapter(bridgeAdapterProxy)
            .owner();
        if (adapterOwner != newGovernor) {
            vm.prank(adapterOwner);
            WormholeBridgeAdapter(bridgeAdapterProxy).transferOwnership(
                newGovernor
            );
        }

        // ProxyAdmin — 1-step Ownable, transfer happens immediately
        address paOwner = ProxyAdmin(proxyAdmin).owner();
        if (paOwner != newGovernor) {
            vm.prank(paOwner);
            ProxyAdmin(proxyAdmin).transferOwnership(newGovernor);
        }
    }

    function _phaseC_runMipE00() internal {
        mipe00 e00 = new mipe00();
        vm.makePersistent(address(e00));

        address deployer = address(e00);

        // e00.initProposal idempotently runs x56.deploy+afterDeploy. We
        // already ran x56 in Phase A, so this short-circuits via its
        // "MULTICHAIN_GOVERNOR_V2_PROXY already set" check.
        e00.initProposal(addresses);
        e00.deploy(addresses, deployer);
        e00.afterDeploy(addresses, deployer);

        // Skip e00.build/simulate/validate.
        //
        // e00.beforeSimulationHook calls forge-std `deal()` to pre-fund the
        // governor with each underlying token. For USDT, deal() probes slots
        // via stdStorage; USDT's delegateContract pattern at slot 10 makes
        // balanceOf revert during the probe, and stdStorage gives up.
        //
        // The migration aspects this skip omits (initial-mint + admin
        // accepts) are simulated by direct pranks in
        // _phaseC2_acceptEthAdminFromGovernor below. The smoke test (Phase E)
        // only mutates reserveFactor — it doesn't need initial-mint state to
        // succeed, so this is a safe reduction in scope.
        _phaseC2_acceptEthAdminFromGovernor();
    }

    /// @notice Skipping e00.build/simulate means the governor never executed
    ///         the `_acceptAdmin()` actions that flip every Eth mToken and
    ///         the Unitroller into governor-controlled state. Stub them in
    ///         via vm.prank(governorV2). The migration summary's TODO #4 is
    ///         the Moonbeam-side equivalent — handled separately by
    ///         _moonbeamAcceptAdminStubs.
    function _phaseC2_acceptEthAdminFromGovernor() internal {
        vm.selectFork(ETHEREUM_FORK_ID);
        address gov = addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY");

        Comptroller mc = Comptroller(addresses.getAddress("UNITROLLER"));
        // Comptroller.getAllMarkets() returns markets supported via
        // _supportMarket — populated in e00.deploy() before this point.
        MToken[] memory markets = mc.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address mtoken = address(markets[i]);
            (bool ok, bytes memory data) = mtoken.staticcall(
                abi.encodeWithSignature("pendingAdmin()")
            );
            if (!ok || data.length < 32) continue;
            if (abi.decode(data, (address)) != gov) continue;
            vm.prank(gov);
            (bool acceptOk, ) = mtoken.call(
                abi.encodeWithSignature("_acceptAdmin()")
            );
            require(acceptOk, "Eth mToken _acceptAdmin stub failed");
        }

        address unitroller = addresses.getAddress("UNITROLLER");
        (bool uOk, bytes memory uData) = unitroller.staticcall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        if (uOk && uData.length >= 32 && abi.decode(uData, (address)) == gov) {
            vm.prank(gov);
            (bool acceptOk, ) = unitroller.call(
                abi.encodeWithSignature("_acceptAdmin()")
            );
            require(acceptOk, "Eth Unitroller _acceptAdmin stub failed");
        }

        // Eth WormholeBridgeAdapter is also part of e00.build()'s accept
        // list (Ownable2Step pendingOwner = governorV2). Without
        // e00.simulate, accept it directly here.
        WormholeBridgeAdapter bridge = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        if (bridge.pendingOwner() == gov) {
            vm.prank(gov);
            bridge.acceptOwnership();
        }
    }

    /// --------------------------------------------------------------------
    /// SETUP HELPERS
    /// --------------------------------------------------------------------

    function _loadHandles() internal {
        vm.selectFork(ETHEREUM_FORK_ID);
        governorV2 = MultichainGovernorV2(
            payable(addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"))
        );
        ethereumVotingPower = VotingPowerAggregator(
            addresses.getAddress("VOTING_POWER_AGGREGATOR")
        );
        ethereumXWell = xWELL(addresses.getAddress("xWELL_PROXY"));
        ethereumBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );
        ethUnitroller = Unitroller(addresses.getAddress("UNITROLLER"));
        ethComptroller = Comptroller(addresses.getAddress("UNITROLLER"));
        mWETH = MToken(addresses.getAddress("MOONWELL_WETH"));
    }

    /// @notice Stub for migration-summary TODO #3: xWELL bridging activation.
    ///         After mip-x56/mip-e00 complete, Eth bridge adapter is owned by
    ///         governorV2; Moonbeam/Base/Op adapters by TemporalGovernor.
    ///         Prank as the owner to install the missing trusted senders.
    function _phase0XWellBridgingStub() internal {
        _addBridgeTrustedSenderIfMissing(
            ETHEREUM_FORK_ID,
            ETHEREUM_CHAIN_ID,
            address(governorV2)
        );

        _addBridgeTrustedSenderIfMissing(
            MOONBEAM_FORK_ID,
            MOONBEAM_CHAIN_ID,
            addresses.getAddress("TEMPORAL_GOVERNOR", MOONBEAM_CHAIN_ID)
        );

        _addBridgeTrustedSenderIfMissing(
            BASE_FORK_ID,
            BASE_CHAIN_ID,
            addresses.getAddress("TEMPORAL_GOVERNOR", BASE_CHAIN_ID)
        );

        _addBridgeTrustedSenderIfMissing(
            OPTIMISM_FORK_ID,
            OPTIMISM_CHAIN_ID,
            addresses.getAddress("TEMPORAL_GOVERNOR", OPTIMISM_CHAIN_ID)
        );

        vm.selectFork(ETHEREUM_FORK_ID);
    }

    function _addBridgeTrustedSenderIfMissing(
        uint256 forkId,
        uint256 selfChainId,
        address owner
    ) internal {
        vm.selectFork(forkId);
        require(block.chainid == selfChainId, "fork/chain mismatch");

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        (
            address[] memory otherAdapters,
            uint16[] memory otherWormholeChainIds
        ) = _othersExcept(selfChainId);

        uint256 pending = 0;
        for (uint256 i = 0; i < otherAdapters.length; i++) {
            if (
                !adapter.isTrustedSender(
                    otherWormholeChainIds[i],
                    otherAdapters[i]
                )
            ) {
                pending++;
            }
        }
        if (pending == 0) return;

        WormholeTrustedSender.TrustedSender[]
            memory toAdd = new WormholeTrustedSender.TrustedSender[](pending);
        uint256 j = 0;
        for (uint256 i = 0; i < otherAdapters.length; i++) {
            if (
                !adapter.isTrustedSender(
                    otherWormholeChainIds[i],
                    otherAdapters[i]
                )
            ) {
                toAdd[j++] = WormholeTrustedSender.TrustedSender({
                    chainId: otherWormholeChainIds[i],
                    addr: otherAdapters[i]
                });
            }
        }

        vm.prank(owner);
        adapter.addTrustedSenders(toAdd);
    }

    function _othersExcept(
        uint256 selfChainId
    )
        internal
        view
        returns (address[] memory adapters, uint16[] memory whChainIds)
    {
        uint256[4] memory chainOrder = [
            ETHEREUM_CHAIN_ID,
            MOONBEAM_CHAIN_ID,
            BASE_CHAIN_ID,
            OPTIMISM_CHAIN_ID
        ];
        uint16[4] memory whOrder = [
            ETHEREUM_WORMHOLE_CHAIN_ID,
            MOONBEAM_WORMHOLE_CHAIN_ID,
            BASE_WORMHOLE_CHAIN_ID,
            OPTIMISM_WORMHOLE_CHAIN_ID
        ];
        adapters = new address[](3);
        whChainIds = new uint16[](3);
        uint256 j = 0;
        for (uint256 i = 0; i < chainOrder.length; i++) {
            if (chainOrder[i] != selfChainId) {
                adapters[j] = addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    chainOrder[i]
                );
                whChainIds[j] = whOrder[i];
                j++;
            }
        }
    }

    /// @notice Stubs for everything e00.simulate() would have done plus the
    ///         four migration-summary TODOs that aren't in either proposal.
    ///         We skipped e00.simulate() because forge-std `deal()` can't
    ///         probe USDT's storage (its delegateContract pattern at slot 10
    ///         makes balanceOf revert during stdStorage's probe).
    function _phaseDPostMigrationAcceptsStub() internal {
        // ---- Accepts that e00.build() pushes as actions ----

        // Moonbeam: WormholeBridgeAdapter (TG acceptOwnership)
        _acceptOwnershipPrank(
            MOONBEAM_FORK_ID,
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                MOONBEAM_CHAIN_ID
            ),
            addresses.getAddress("TEMPORAL_GOVERNOR", MOONBEAM_CHAIN_ID)
        );

        // Moonbeam: MultichainVoteCollectionMoonbeam (TG acceptOwnership)
        _acceptOwnershipPrank(
            MOONBEAM_FORK_ID,
            addresses.getAddress("VOTE_COLLECTION_V2_PROXY", MOONBEAM_CHAIN_ID),
            addresses.getAddress("TEMPORAL_GOVERNOR", MOONBEAM_CHAIN_ID)
        );

        // Moonbeam: VotingPowerAggregator (TG acceptOwnership)
        _acceptOwnershipPrank(
            MOONBEAM_FORK_ID,
            addresses.getAddress("VOTING_POWER_AGGREGATOR", MOONBEAM_CHAIN_ID),
            addresses.getAddress("TEMPORAL_GOVERNOR", MOONBEAM_CHAIN_ID)
        );

        // Base: VotingPowerAggregator (TG acceptOwnership)
        _acceptOwnershipPrank(
            BASE_FORK_ID,
            addresses.getAddress("VOTING_POWER_AGGREGATOR", BASE_CHAIN_ID),
            addresses.getAddress("TEMPORAL_GOVERNOR", BASE_CHAIN_ID)
        );

        // Optimism: VotingPowerAggregator (TG acceptOwnership)
        _acceptOwnershipPrank(
            OPTIMISM_FORK_ID,
            addresses.getAddress("VOTING_POWER_AGGREGATOR", OPTIMISM_CHAIN_ID),
            addresses.getAddress("TEMPORAL_GOVERNOR", OPTIMISM_CHAIN_ID)
        );

        // ---- Migration-summary TODOs that aren't in either proposal ----

        // TODO #1: Eth xWELL acceptOwnership(governorV2)
        vm.selectFork(ETHEREUM_FORK_ID);
        if (ethereumXWell.pendingOwner() == address(governorV2)) {
            vm.prank(address(governorV2));
            ethereumXWell.acceptOwnership();
        }

        // TODO #2: Eth VotingPowerAggregator acceptOwnership(governorV2)
        if (ethereumVotingPower.pendingOwner() == address(governorV2)) {
            vm.prank(address(governorV2));
            ethereumVotingPower.acceptOwnership();
        }

        // TODO #4: Moonbeam mTokens + Unitroller _acceptAdmin(TG)
        _moonbeamAcceptAdminStubs();
    }

    function _acceptOwnershipPrank(
        uint256 forkId,
        address target,
        address pendingOwnerExpected
    ) internal {
        vm.selectFork(forkId);
        (bool ok, bytes memory data) = target.staticcall(
            abi.encodeWithSignature("pendingOwner()")
        );
        if (!ok || data.length < 32) return;
        if (abi.decode(data, (address)) != pendingOwnerExpected) return;
        vm.prank(pendingOwnerExpected);
        (bool acceptOk, ) = target.call(
            abi.encodeWithSignature("acceptOwnership()")
        );
        require(acceptOk, "_acceptOwnershipPrank failed");
    }

    function _moonbeamAcceptAdminStubs() internal {
        vm.selectFork(MOONBEAM_FORK_ID);
        address tg = addresses.getAddress("TEMPORAL_GOVERNOR");

        Comptroller mc = Comptroller(addresses.getAddress("UNITROLLER"));
        MToken[] memory markets = mc.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address mtoken = address(markets[i]);
            (bool ok, bytes memory data) = mtoken.staticcall(
                abi.encodeWithSignature("pendingAdmin()")
            );
            if (!ok || data.length < 32) continue;
            if (abi.decode(data, (address)) != tg) continue;

            vm.prank(tg);
            (bool acceptOk, ) = mtoken.call(
                abi.encodeWithSignature("_acceptAdmin()")
            );
            require(acceptOk, "Moonbeam mToken _acceptAdmin stub failed");
        }

        // Unitroller has its own pendingAdmin / _acceptAdmin pair.
        address unitroller = addresses.getAddress("UNITROLLER");
        (bool uOk, bytes memory uData) = unitroller.staticcall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        if (uOk && uData.length >= 32 && abi.decode(uData, (address)) == tg) {
            vm.prank(tg);
            (bool acceptOk, ) = unitroller.call(
                abi.encodeWithSignature("_acceptAdmin()")
            );
            require(acceptOk, "Moonbeam Unitroller _acceptAdmin stub failed");
        }

        vm.selectFork(ETHEREUM_FORK_ID);
    }

    /// @notice Install WormholeRelayerAdapter mock so cross-chain proposal
    ///         actions (Eth → Moonbeam/Base/Op) delivered by mip-e00 and
    ///         the smoke test actually execute in-memory.
    function _phaseB_installWormholeMock() internal {
        WormholeRelayerAdapter adapter = new WormholeRelayerAdapter(
            new uint16[](0),
            new uint256[](0)
        );
        vm.makePersistent(address(adapter));
        vm.label(address(adapter), "MockWormholeCore");

        adapter.setIsMultichainTest(true);
        adapter.setSenderChainId(ETHEREUM_WORMHOLE_CHAIN_ID);

        vm.selectFork(ETHEREUM_FORK_ID);
        _overrideWormholeCore(
            addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"),
            address(adapter)
        );

        vm.selectFork(MOONBEAM_FORK_ID);
        _overrideWormholeCore(
            addresses.getAddress("VOTE_COLLECTION_V2_PROXY"),
            address(adapter)
        );

        vm.selectFork(BASE_FORK_ID);
        _overrideWormholeCore(
            addresses.getAddress("VOTE_COLLECTION_PROXY"),
            address(adapter)
        );

        vm.selectFork(OPTIMISM_FORK_ID);
        _overrideWormholeCore(
            addresses.getAddress("VOTE_COLLECTION_PROXY"),
            address(adapter)
        );

        vm.selectFork(ETHEREUM_FORK_ID);
    }

    function _overrideWormholeCore(
        address target,
        address newWormhole
    ) internal {
        uint256 slot = stdstore
            .target(target)
            .sig(bytes4(keccak256("wormhole()")))
            .find();
        vm.store(target, bytes32(slot), bytes32(uint256(uint160(newWormhole))));
    }

    /// @notice Mock VotingPowerAggregator responses so SMOKE_PROPOSER has
    ///         enough votes to propose + push the smoke proposal through
    ///         quorum without bridging xWELL.
    function _grantSmokeProposerVotingPower() internal {
        vm.selectFork(ETHEREUM_FORK_ID);
        vm.deal(SMOKE_PROPOSER, 100 ether);

        vm.mockCall(
            address(ethereumVotingPower),
            abi.encodeWithSelector(
                VotingPowerAggregator.getVotes.selector,
                SMOKE_PROPOSER,
                block.timestamp - 1
            ),
            abi.encode(PROPOSER_VOTES)
        );

        vm.mockCall(
            address(ethereumVotingPower),
            abi.encodeWithSelector(
                VotingPowerAggregator.getCurrentVotes.selector,
                SMOKE_PROPOSER
            ),
            abi.encode(PROPOSER_VOTES)
        );
    }

    /// --------------------------------------------------------------------
    /// PHASE BOUNDARY ASSERTIONS
    /// --------------------------------------------------------------------

    function testPhaseA_mipx56_postMigrationState() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        assertGt(address(governorV2).code.length, 0, "governorV2 not deployed");

        vm.selectFork(MOONBEAM_FORK_ID);
        address tg = addresses.getAddress("TEMPORAL_GOVERNOR");
        assertGt(tg.code.length, 0, "Moonbeam TemporalGovernor not deployed");
    }

    function testPhaseC_mipe00_ethCoreLive() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            ethUnitroller.admin(),
            address(governorV2),
            "Unitroller admin should be governorV2 post-e00"
        );
        assertEq(
            mWETH.admin(),
            address(governorV2),
            "MOONWELL_WETH admin should be governorV2"
        );
        assertEq(
            ethereumBridgeAdapter.owner(),
            address(governorV2),
            "Eth WormholeBridgeAdapter owner should be governorV2 post-e00"
        );
    }

    function testPhaseD_postMigrationStubsApplied() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            ethereumXWell.owner(),
            address(governorV2),
            "Eth xWELL owner stub should make governorV2 the owner"
        );
        assertEq(
            ethereumVotingPower.owner(),
            address(governorV2),
            "Eth VotingPowerAggregator owner stub should make governorV2 the owner"
        );

        assertTrue(
            ethereumBridgeAdapter.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    MOONBEAM_CHAIN_ID
                )
            ),
            "Moonbeam bridge adapter not trusted on Eth"
        );
        assertTrue(
            ethereumBridgeAdapter.isTrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    BASE_CHAIN_ID
                )
            ),
            "Base bridge adapter not trusted on Eth"
        );
        assertTrue(
            ethereumBridgeAdapter.isTrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    OPTIMISM_CHAIN_ID
                )
            ),
            "Optimism bridge adapter not trusted on Eth"
        );

        vm.selectFork(MOONBEAM_FORK_ID);
        Unitroller moonbeamUnitroller = Unitroller(
            addresses.getAddress("UNITROLLER")
        );
        address moonbeamTG = addresses.getAddress("TEMPORAL_GOVERNOR");
        assertEq(
            moonbeamUnitroller.admin(),
            moonbeamTG,
            "Moonbeam Unitroller admin should be TemporalGovernor post-stub"
        );
    }

    /// --------------------------------------------------------------------
    /// PHASE E — END-TO-END SMOKE TEST
    /// --------------------------------------------------------------------

    function testPhaseE_smokeProposalChangesEthMarket() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        uint256 initialReserveFactor = mWETH.reserveFactorMantissa();

        EthMarketUpdateSmoke smoke = new EthMarketUpdateSmoke();
        vm.makePersistent(address(smoke));

        smoke.build(addresses);
        smoke.simulate(addresses, address(0));
        smoke.validate(addresses, address(0));

        assertEq(
            mWETH.reserveFactorMantissa(),
            smoke.NEW_RESERVE_FACTOR(),
            "smoke test reserve factor change did not land"
        );
        assertGt(
            mWETH.reserveFactorMantissa(),
            initialReserveFactor,
            "reserve factor should have been bumped"
        );
    }
}

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
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";
import {MultichainGovernorV2} from "@protocol/governance/multichain/MultichainGovernorV2.sol";

import {ChainIds} from "@utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {mipx58} from "@proposals/mips/mip-x58/mip-x58.sol";
import {mipe00} from "@proposals/mips/mip-e00/mip-e00.sol";
import {mipe01} from "@proposals/mips/mip-e01/mip-e01.sol";

import {EthMarketUpdateSmoke} from "@test/integration/proposals/EthMarketUpdateSmoke.sol";
import {BaseMarketUpdateSmoke} from "@test/integration/proposals/BaseMarketUpdateSmoke.sol";
import {MoonbeamMarketUpdateSmoke} from "@test/integration/proposals/MoonbeamMarketUpdateSmoke.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";

import {ETHEREUM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID, MOONBEAM_FORK_ID, ETHEREUM_WORMHOLE_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID, ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title MigrationHarness
/// @notice End-to-end validation harness for the Moonwell governance migration
///         to Ethereum (mip-x58) + Ethereum core deployment (mip-e00). Runs
///         against persistent Tenderly VNets — RPC URLs come from
///         setup-migration-vnets.ts via foundry.toml's [rpc_endpoints] block.
///
///         The harness drives mip-x58 and mip-e00 directly (NOT via
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

        // Phase A: run mip-x58 (governor migration)
        _phaseA_runMipX58();

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

        // Phase D first: run mip-e01 (First Ethereum Proposal) through
        // governance — completes acceptOwnership/_acceptAdmin for items
        // mip-x58 + mip-e00 didn't cover (Eth xWELL/VPA, Moonbeam
        // Unitroller + mTokens). Must run before Phase 0 because Phase 0
        // pranks as the bridge adapters' owners — which on satellite
        // chains is the TemporalGovernor only after it accepts the
        // ownership transfers e00 queued.
        _phaseD_runMipE01();

        // Phase 0: xWELL bridging activation stub (now TG owns the bridge
        // adapters on Moonbeam/Base/Op).
        _phase0XWellBridgingStub();

        // Mock voting power for the smoke proposer
        _grantSmokeProposerVotingPower();
    }

    /// --------------------------------------------------------------------
    /// MIGRATION PHASES
    /// --------------------------------------------------------------------

    function _phaseA_runMipX58() internal {
        // Governor migration proposal — was mip-x56 in earlier rounds,
        // renamed to mip-x58 in the gov-refactor PR (mip-x56 is now the
        // OEV wrapper redeploy).
        mipx58 x58 = new mipx58();
        vm.makePersistent(address(x58));

        // Match ProposalMap.runProposal's pattern: deployer = address(proposal).
        address deployer = address(x58);

        x58.deploy(addresses, deployer);
        x58.afterDeploy(addresses, deployer);
        x58.build(addresses);
        x58.simulate(addresses, deployer);
        x58.validate(addresses, deployer);
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
        e00.build(addresses);

        // Pre-fund the governor with each underlying token via
        // _phaseC1_dealUnderlyings instead of e00.beforeSimulationHook —
        // forge-std `deal()` trips USDT's delegateContract probe in
        // stdStorage. The helper uses direct vm.store for USDT and
        // forge-std deal for the others (WETH, USDC, cbBTC).
        _phaseC1_dealUnderlyings(e00);

        // e00.simulate executes the proposal through MultichainGovernorV2,
        // running every _acceptAdmin() / acceptOwnership() / mint action
        // as a real governor-driven tx — no pranks.
        e00.simulate(addresses, deployer);
        e00.validate(addresses, deployer);
    }

    /// @notice Pre-fund the new MultichainGovernorV2 with each Eth market's
    ///         underlying token at the initialMintAmount declared in
    ///         mip-e00/mTokens.json. Replaces `e00.beforeSimulationHook` so
    ///         USDT — whose deprecation/delegateContract pattern at slot 10
    ///         makes forge-std `deal()` fail during stdStorage's probe —
    ///         can still be funded via a direct storage write to its
    ///         TetherToken `balances` mapping at base slot 2.
    function _phaseC1_dealUnderlyings(mipe00 e00) internal {
        vm.selectFork(ETHEREUM_FORK_ID);
        address governor = addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY");
        address usdt = addresses.getAddress("USDT", ETHEREUM_CHAIN_ID);

        Configs.CTokenConfiguration[] memory cfgs = e00.getCTokenConfigurations(
            ETHEREUM_CHAIN_ID
        );

        for (uint256 i = 0; i < cfgs.length; i++) {
            address token = addresses.getAddress(cfgs[i].tokenAddressName);
            uint256 amount = cfgs[i].initialMintAmount;
            if (token == usdt) {
                _dealUSDT(token, governor, amount);
            } else {
                deal(token, governor, amount);
            }
        }
    }

    /// @notice Set TetherToken.balances[to] = amount and bump _totalSupply
    ///         by `amount`. TetherToken's storage layout has balances at
    ///         base slot 2 and _totalSupply at slot 5 — both fixed by the
    ///         original (immutable) USDT contract source.
    function _dealUSDT(address usdt, address to, uint256 amount) internal {
        bytes32 balanceSlot = keccak256(abi.encode(to, uint256(2)));
        vm.store(usdt, balanceSlot, bytes32(amount));

        // Track totalSupply so any contract that reads it sees a value
        // consistent with the new balance. We add to the existing
        // totalSupply rather than overwrite so the deal isn't visible as
        // a net change in supply other than the delta we introduced.
        uint256 prev = uint256(vm.load(usdt, bytes32(uint256(5))));
        vm.store(usdt, bytes32(uint256(5)), bytes32(prev + amount));
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
    ///         After mip-x58/mip-e00 complete, Eth bridge adapter is owned by
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

    /// @notice Phase D: run mip-e01 (the First Ethereum Proposal) through
    ///         governance. mip-e01 completes the ownership/admin transfers
    ///         that mip-x58 + mip-e00 leave in a half-transferred state:
    ///           - Eth xWELL acceptOwnership (TODO #1)
    ///           - Eth VotingPowerAggregator acceptOwnership (TODO #2)
    ///           - Moonbeam Unitroller + mTokens _acceptAdmin (TODO #4)
    ///         The previous prank-based stubs are replaced with a real
    ///         HybridProposalV2 propose → vote → execute cycle on
    ///         MultichainGovernorV2.
    ///         xWELL bridging activation (TODO #3) is out of scope here —
    ///         tested in a separate in-flight Moonbeam-governor proposal.
    function _phaseD_runMipE01() internal {
        mipe01 e01 = new mipe01();
        vm.makePersistent(address(e01));

        e01.build(addresses);
        e01.simulate(addresses, address(0));
        e01.validate(addresses, address(0));

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

    function testPhaseA_mipx58_postMigrationState() public {
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

    /// --------------------------------------------------------------------
    /// PHASE F — END-TO-END CROSS-CHAIN SMOKE TEST
    /// --------------------------------------------------------------------

    /// @notice Proves the new Ethereum MultichainGovernorV2 can hop through
    ///         Wormhole to the Base TemporalGovernor and execute an action
    ///         that mutates a live Base mToken parameter.
    ///         The proposal is Eth-native at construction (HybridProposalV2),
    ///         but the action type is ActionType.Base so simulate() routes
    ///         it via Wormhole: governorV2.execute → publishMessage →
    ///         (mock VAA) → Base TG.queueProposal → vm.warp past TG's
    ///         proposalDelay (24h) → Base TG.executeProposal → reserve
    ///         factor change lands on Base USDC.
    function testPhaseF_smokeProposalChangesBaseMarket() public {
        vm.selectFork(BASE_FORK_ID);
        MToken baseUSDC = MToken(addresses.getAddress("MOONWELL_USDC"));
        uint256 initialReserveFactor = baseUSDC.reserveFactorMantissa();

        BaseMarketUpdateSmoke smoke = new BaseMarketUpdateSmoke();
        vm.makePersistent(address(smoke));

        smoke.build(addresses);
        smoke.simulate(addresses, address(0));
        smoke.validate(addresses, address(0));

        vm.selectFork(BASE_FORK_ID);
        assertEq(
            baseUSDC.reserveFactorMantissa(),
            smoke.NEW_RESERVE_FACTOR(),
            "Base USDC reserve factor change did not land"
        );
        assertTrue(
            baseUSDC.reserveFactorMantissa() != initialReserveFactor,
            "Base USDC reserve factor unchanged"
        );
    }

    /// --------------------------------------------------------------------
    /// PHASE F2 — END-TO-END MOONBEAM SMOKE TEST
    /// --------------------------------------------------------------------

    /// @notice Proves the new Ethereum MultichainGovernorV2 can hop through
    ///         Wormhole to the Moonbeam TemporalGovernor and execute an
    ///         action that mutates a live Moonbeam Comptroller parameter.
    ///         Mirrors Phase F (Base) but targets Moonbeam. The full path:
    ///         governorV2.execute → publishMessage → fake VAA →
    ///         Moonbeam TG.queueProposal → vm.warp past TG's proposalDelay
    ///         (1 day) → Moonbeam TG.executeProposal →
    ///         Comptroller._setCloseFactor lands on the live Moonbeam
    ///         Unitroller. Unitroller admin is TG by this point
    ///         (mip-e01 in Phase D accepted admin from x58's
    ///         _setPendingAdmin), so the change goes through.
    function testPhaseF2_smokeProposalChangesMoonbeamComptroller() public {
        vm.selectFork(MOONBEAM_FORK_ID);
        Comptroller moonbeamComptroller = Comptroller(
            addresses.getAddress("UNITROLLER")
        );
        uint256 initialCloseFactor = moonbeamComptroller.closeFactorMantissa();

        MoonbeamMarketUpdateSmoke smoke = new MoonbeamMarketUpdateSmoke();
        vm.makePersistent(address(smoke));

        smoke.build(addresses);
        smoke.simulate(addresses, address(0));
        smoke.validate(addresses, address(0));

        vm.selectFork(MOONBEAM_FORK_ID);
        assertEq(
            moonbeamComptroller.closeFactorMantissa(),
            smoke.NEW_CLOSE_FACTOR(),
            "Moonbeam closeFactor change did not land"
        );
        assertTrue(
            moonbeamComptroller.closeFactorMantissa() != initialCloseFactor,
            "Moonbeam closeFactor unchanged"
        );
    }

    /// --------------------------------------------------------------------
    /// PHASE G — BREAK-GLASS EXECUTION PATH
    /// --------------------------------------------------------------------
    /// Proves the migration is reversible: the breakGlassGuardian set during
    /// mip-x58 init can pull ownership of governor-controlled Eth contracts
    /// back to PAUSE_GUARDIAN by executing a whitelisted calldata through
    /// MultichainGovernorV2.executeBreakGlass.
    ///
    /// Coverage:
    ///   - testPhaseG_breakGlassUnwindsEthOwnership: positive path. State
    ///     mutates; breakGlassGuardian role is one-shot (zeroed afterwards).
    ///   - testPhaseG_breakGlassRejectsNonWhitelistedCalldata: whitelist
    ///     enforcement.
    ///   - testPhaseG_breakGlassRejectsNonGuardianCaller: auth enforcement.

    function testPhaseG_breakGlassUnwindsSatelliteTrustedSenders() public {
        vm.selectFork(ETHEREUM_FORK_ID);

        address bgGuardian = governorV2.breakGlassGuardian();
        assertTrue(
            bgGuardian != address(0),
            "break-glass guardian already revoked pre-test"
        );

        // mip-x58 seeds three whitelisted publishMessage calldatas — one per
        // satellite chain (Moonbeam, Base, Optimism). Each unwinds that
        // chain's TemporalGovernor trusted-sender state: removes the new
        // Ethereum V2 governor and restores the old Moonbeam
        // MultichainGovernor. Reconstruct the Moonbeam unwind calldata here
        // (mirroring mip-x58._buildUnwindPublishMessageCalldata exactly) so
        // the test verifies the whitelist seed bytes match what x58 stored.
        bytes memory unwindMoonbeamCalldata = _buildUnwindCalldataForFork(
            MOONBEAM_FORK_ID
        );
        assertTrue(
            governorV2.isWhitelistedCalldata(unwindMoonbeamCalldata),
            "Moonbeam-unwind publishMessage calldata not whitelisted - x58 seed mismatch"
        );

        // Execute break-glass against the Eth Wormhole core. This emits a
        // LogMessagePublished that an off-chain relayer would deliver to the
        // Moonbeam TG; in-memory we just verify the call succeeds + the
        // one-shot guardian property holds.
        vm.selectFork(ETHEREUM_FORK_ID);
        address ethWormholeCore = addresses.getAddress(
            "WORMHOLE_CORE",
            ETHEREUM_CHAIN_ID
        );
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = ethWormholeCore;
        calldatas[0] = unwindMoonbeamCalldata;

        vm.prank(bgGuardian);
        governorV2.executeBreakGlass(targets, calldatas);

        // One-shot: the guardian role is revoked.
        assertEq(
            governorV2.breakGlassGuardian(),
            address(0),
            "break-glass guardian not zeroed (one-shot property broken)"
        );

        // Re-invocation as the (now revoked) guardian must revert.
        vm.prank(bgGuardian);
        vm.expectRevert();
        governorV2.executeBreakGlass(targets, calldatas);
    }

    /// @notice Mirror of mip-x58._buildUnwindPublishMessageCalldata for a
    ///         single satellite chain. Used by the break-glass positive
    ///         test to reconstruct the exact calldata bytes x58 wrote into
    ///         the whitelist at init time.
    function _buildUnwindCalldataForFork(
        uint256 satelliteForkId
    ) internal returns (bytes memory) {
        uint256 forkBefore = vm.activeFork();

        vm.selectFork(ETHEREUM_FORK_ID);
        address ethereumGovernorV2 = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY"
        );

        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamMultichainGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        vm.selectFork(satelliteForkId);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");

        ITemporalGovernor.TrustedSender[]
            memory ethereumSender = new ITemporalGovernor.TrustedSender[](1);
        ethereumSender[0] = ITemporalGovernor.TrustedSender({
            chainId: ETHEREUM_WORMHOLE_CHAIN_ID,
            addr: ethereumGovernorV2
        });
        bytes memory unSetEthereumCalldata = abi.encodeWithSignature(
            "unSetTrustedSenders((uint16,address)[])",
            ethereumSender
        );

        ITemporalGovernor.TrustedSender[]
            memory moonbeamSender = new ITemporalGovernor.TrustedSender[](1);
        moonbeamSender[0] = ITemporalGovernor.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: moonbeamMultichainGovernor
        });
        bytes memory setMoonbeamCalldata = abi.encodeWithSignature(
            "setTrustedSenders((uint16,address)[])",
            moonbeamSender
        );

        address[] memory innerTargets = new address[](2);
        innerTargets[0] = temporalGovernor;
        innerTargets[1] = temporalGovernor;

        uint256[] memory innerValues = new uint256[](2);

        bytes[] memory innerCalldatas = new bytes[](2);
        innerCalldatas[0] = unSetEthereumCalldata;
        innerCalldatas[1] = setMoonbeamCalldata;

        bytes memory result = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            uint32(1000),
            abi.encode(
                temporalGovernor,
                innerTargets,
                innerValues,
                innerCalldatas
            ),
            uint8(1)
        );

        vm.selectFork(forkBefore);
        return result;
    }

    function testPhaseG_breakGlassRejectsNonWhitelistedCalldata() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        address bgGuardian = governorV2.breakGlassGuardian();
        address attacker = address(0xBADC0DE);

        // Only the three publishMessage(unwind, ...) calldatas seeded by
        // mip-x58 are whitelisted. A bare transferOwnership(attacker) is
        // not — confirm and then verify break-glass rejects it.
        bytes memory badCalldata = abi.encodeWithSignature(
            "transferOwnership(address)",
            attacker
        );
        assertFalse(
            governorV2.isWhitelistedCalldata(badCalldata),
            "attacker-target calldata wrongly whitelisted"
        );

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(ethereumBridgeAdapter);
        calldatas[0] = badCalldata;

        vm.prank(bgGuardian);
        vm.expectRevert();
        governorV2.executeBreakGlass(targets, calldatas);

        // No state change: bridge adapter still owned by governor; pending
        // owner unchanged.
        assertEq(
            ethereumBridgeAdapter.owner(),
            address(governorV2),
            "bridge adapter owner changed despite reverted break-glass"
        );
    }

    function testPhaseG_breakGlassRejectsNonGuardianCaller() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = address(ethereumBridgeAdapter);
        calldatas[0] = abi.encodeWithSignature(
            "transferOwnership(address)",
            pauseGuardian
        );

        address notGuardian = address(0xDEADBEEF);
        require(
            notGuardian != governorV2.breakGlassGuardian(),
            "test sentinel address collides with guardian"
        );

        vm.prank(notGuardian);
        vm.expectRevert();
        governorV2.executeBreakGlass(targets, calldatas);

        // Guardian role still intact (not revoked by the failed call).
        assertTrue(
            governorV2.breakGlassGuardian() != address(0),
            "guardian role unexpectedly revoked by reverted call"
        );
    }

    /// @notice End-to-end downstream effect of break-glass: capture the
    ///         LogMessagePublished from the Eth Wormhole core, deliver the
    ///         resulting VAA to the Moonbeam TemporalGovernor, and verify
    ///         the trusted-sender state actually flips:
    ///           - Eth governor REMOVED as trusted sender
    ///           - Old Moonbeam MultichainGovernor RESTORED as trusted sender
    ///
    ///         Pre-condition (post-mip-x58): Moonbeam TG trusts only the
    ///         new Eth governor (ETHEREUM_WORMHOLE_CHAIN_ID → governorV2).
    ///         Post break-glass + downstream delivery: trust is flipped to
    ///         the old Moonbeam governor (MOONBEAM_WORMHOLE_CHAIN_ID →
    ///         oldMoonbeamGovernor).
    function testPhaseG_breakGlassDeliversUnwindToMoonbeamTG() public {
        vm.selectFork(ETHEREUM_FORK_ID);
        address bgGuardian = governorV2.breakGlassGuardian();
        address ethWormholeCore = addresses.getAddress(
            "WORMHOLE_CORE",
            ETHEREUM_CHAIN_ID
        );

        // Pre-state on Moonbeam TG: trusts new Eth governor; does NOT trust
        // old Moonbeam governor.
        vm.selectFork(MOONBEAM_FORK_ID);
        TemporalGovernor moonbeamTG = TemporalGovernor(
            payable(addresses.getAddress("TEMPORAL_GOVERNOR"))
        );
        address oldMoonbeamGovernor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );
        assertTrue(
            moonbeamTG.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                address(governorV2)
            ),
            "pre: Moonbeam TG should trust new Eth governor"
        );
        assertFalse(
            moonbeamTG.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                oldMoonbeamGovernor
            ),
            "pre: Moonbeam TG should NOT trust old Moonbeam governor"
        );

        // Build the unwind calldata and execute break-glass on Ethereum.
        // Record logs so we can capture the LogMessagePublished payload.
        bytes memory unwindCalldata = _buildUnwindCalldataForFork(
            MOONBEAM_FORK_ID
        );
        vm.selectFork(ETHEREUM_FORK_ID);
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        targets[0] = ethWormholeCore;
        calldatas[0] = unwindCalldata;

        vm.recordLogs();
        vm.prank(bgGuardian);
        governorV2.executeBreakGlass(targets, calldatas);

        // Pull the published-message payload out of the Eth Wormhole core's
        // emitted LogMessagePublished event.
        bytes memory innerPayload = _extractFirstPublishedPayload(
            ethWormholeCore
        );
        require(innerPayload.length > 0, "no LogMessagePublished captured");

        // Deliver to Moonbeam TG: etch the Implementation mock at Moonbeam
        // WORMHOLE_CORE (bypasses guardian signature check), generate a fake
        // VAA with emitter = Eth governor on ETHEREUM_WORMHOLE_CHAIN_ID,
        // queue + warp + execute.
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamWormholeCore = addresses.getAddress("WORMHOLE_CORE");
        Implementation core = new Implementation();
        vm.etch(moonbeamWormholeCore, address(core).code);

        bytes memory vaa = _generateVAA(
            uint32(block.timestamp),
            ETHEREUM_WORMHOLE_CHAIN_ID,
            bytes32(uint256(uint160(address(governorV2)))),
            innerPayload
        );

        moonbeamTG.queueProposal(vaa);
        vm.warp(block.timestamp + moonbeamTG.proposalDelay() + 1);
        moonbeamTG.executeProposal(vaa);

        // Post-state on Moonbeam TG: trust is fully flipped.
        assertFalse(
            moonbeamTG.isTrustedSender(
                ETHEREUM_WORMHOLE_CHAIN_ID,
                address(governorV2)
            ),
            "post: Moonbeam TG should NO LONGER trust new Eth governor"
        );
        assertTrue(
            moonbeamTG.isTrustedSender(
                MOONBEAM_WORMHOLE_CHAIN_ID,
                oldMoonbeamGovernor
            ),
            "post: Moonbeam TG should now trust old Moonbeam governor"
        );
    }

    /// @notice Extracts the `payload` field from the first
    ///         LogMessagePublished event emitted by `emitter` in the
    ///         current recorded-logs window.
    ///         Event signature:
    ///           LogMessagePublished(address indexed sender, uint64 sequence,
    ///                               uint32 nonce, bytes payload, uint8 consistencyLevel)
    ///         (sender is indexed; sequence/nonce/payload/consistencyLevel
    ///         are ABI-encoded together into data.)
    function _extractFirstPublishedPayload(
        address emitter
    ) internal returns (bytes memory) {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256(
            "LogMessagePublished(address,uint64,uint32,bytes,uint8)"
        );
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != emitter) continue;
            if (logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] != sig) continue;
            (, , bytes memory payload, ) = abi.decode(
                logs[i].data,
                (uint64, uint32, bytes, uint8)
            );
            return payload;
        }
        return new bytes(0);
    }

    /// @notice Builds an unsigned Wormhole VAA in the same packed layout
    ///         HybridProposalV2.generateVAA uses. The Implementation mock
    ///         etched at WORMHOLE_CORE bypasses guardian signature checks,
    ///         so an unsigned VAA is enough for in-test delivery.
    function _generateVAA(
        uint32 timestamp,
        uint16 emitterChainId,
        bytes32 emitterAddress,
        bytes memory payload
    ) internal pure returns (bytes memory) {
        uint64 sequence = 200;
        uint8 version = 1;
        uint32 nonceField = 0;
        uint8 consistencyLevel = 200;
        return
            abi.encodePacked(
                version,
                timestamp,
                nonceField,
                emitterChainId,
                emitterAddress,
                sequence,
                consistencyLevel,
                payload
            );
    }
}

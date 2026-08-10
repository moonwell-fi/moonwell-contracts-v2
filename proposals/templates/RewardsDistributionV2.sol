//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID, BASE_CHAIN_ID, ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {xWELLBridgeFeePayer} from "@protocol/xWELL/xWELLBridgeFeePayer.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {ActionType, ProposalAction} from "@proposals/proposalTypes/IProposal.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IMultiRewards} from "@crv-rewards/IMultiRewards.sol";

interface IMerkleCampaignCreator {
    struct CampaignParameters {
        // POPULATED ONCE CREATED
        // ID of the campaign. This can be left as a null bytes32 when creating campaigns
        // on Merkl.
        bytes32 campaignId;
        // CHOSEN BY CAMPAIGN CREATOR
        // Address of the campaign creator, if marked as address(0), it will be overriden with the
        // address of the `msg.sender` creating the campaign
        address creator;
        // Address of the token used as a reward
        address rewardToken;
        // Amount of `rewardToken` to distribute across all the epochs
        // Amount distributed per epoch is `amount/numEpoch`
        uint256 amount;
        // Type of campaign
        uint32 campaignType;
        // Timestamp at which the campaign should start
        uint32 startTimestamp;
        // Duration of the campaign in seconds. Has to be a multiple of EPOCH = 3600
        uint32 duration;
        // Extra data to pass to specify the campaign
        bytes campaignData;
    }

    function campaignId(
        CampaignParameters memory campaignData
    ) external view returns (bytes32);

    function campaign(
        bytes32 campaignId
    ) external view returns (CampaignParameters memory);
}

/// @title RewardsDistributionV2Template
/// @notice Rewards distribution template for the Ethereum-hub governance era
/// (MultichainGovernorV2). Ethereum (chain 1) is the SOURCE chain: the
/// FOUNDATION_MULTISIG funds the governor (for bridging to Base) and the
/// Ethereum MRD directly via xWELL transferFrom. Base and Optimism remain
/// external destination chains executed via their TemporalGovernors.
/// Moonbeam is now a pure destination chain in wind-down mode (comptroller
/// reward speeds + safety module only — no StellaSwap, no bridging).
contract RewardsDistributionV2Template is HybridProposalV2, Networks {
    using SafeCast for *;
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;
    using ProposalActions for *;
    using stdStorage for StdStorage;

    /// @notice xWELL bridged out from Ethereum via the WormholeBridgeAdapter
    /// on-chain-quoted path. JSON keys (alphabetical): amount, network, target
    struct BridgeOut {
        uint256 amount;
        uint256 network;
        string target;
    }

    struct TransferFrom {
        uint256 amount;
        string from;
        string to;
        string token;
    }

    struct TransferReserves {
        uint256 amount;
        string market;
        string to;
    }

    struct WithdrawWell {
        uint256 amount;
        string to;
    }

    struct SetRewardSpeed {
        string market;
        int256 newBorrowSpeed;
        int256 newSupplySpeed;
        uint256 rewardType;
    }

    struct SetMRDRewardSpeed {
        string emissionToken;
        string market;
        int256 newBorrowSpeed;
        int256 newEndTime;
        int256 newSupplySpeed;
    }

    struct MultiRewarder {
        string distributor;
        uint256 duration;
        uint256 reward;
        string rewardToken;
        string vault;
    }

    struct InitSale {
        uint256 auctionPeriod;
        uint256 delay;
        uint256 miniAuctionPeriod;
        uint256 periodMaxDiscount;
        int256 periodStartingPremium;
        string[] reserveAutomationContracts;
    }

    struct MekleCampaign {
        uint256 amount;
        string campaignData;
        uint32 campaignType;
        uint32 duration;
        string rewardToken;
        uint32 startTimestamp;
    }

    /// @notice Moonbeam is now a pure destination chain (wind-down).
    /// Parsed per-key from the ".1284" object.
    struct JsonSpecMoonbeam {
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
        WithdrawWell[] withdrawWell;
    }

    struct JsonSpecExternalChain {
        InitSale initSale;
        MultiRewarder[] multiRewarder;
        SetMRDRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
        TransferReserves[] transferReserves;
        WithdrawWell[] withdrawWell;
        MekleCampaign[] merkleCampaigns;
    }

    JsonSpecMoonbeam moonbeamActions;

    /// @notice xWELL bridge-outs executed on Ethereum (the source chain)
    BridgeOut[] public bridgeOuts;

    uint256 chainId;
    uint256 startTimeStamp;
    uint256 endTimeStamp;

    // leftover reward rate on USDC morpho vault from previous proposal
    uint256 leftoverRewardRate;
    uint256 leftoverPeriodFinish;

    mapping(uint256 => JsonSpecExternalChain) externalChainActions;

    /// @notice we save this value to check if the transferFrom amount was successfully transferred
    mapping(address => uint256) public wellBalancesBefore;

    /// @notice Track reserve automation contract balances before proposal execution
    mapping(address => uint256) public reserveAutomationBalancesBefore;

    /// @notice per-ActionType map of per-type action indices where a chunk
    /// boundary is FORBIDDEN because cutting there would split a dependent
    /// action sequence (a reduce->transfer reserve pair, a multiRewarder
    /// approve->notify group, or an approve->accept->create merkle triple)
    /// across two wormhole VAAs. Populated during build by _markAtomicGroup;
    /// read by the generic chunker in _computeChunkStarts.
    mapping(uint8 => mapping(uint256 => bool)) private _unsafeCut;

    /// @notice per-ActionType 1-based per-type index of the first
    /// withdrawWell action whose destination is the TEMPORAL_GOVERNOR
    /// (0 = none). Later same-chain actions (multiRewarder approvals, merkle
    /// campaign spends) may rely on that withdrawal replenishing the TG
    /// balance, and chunks execute as unordered independent VAAs — so the
    /// whole span from that withdrawal to the end of the chain's bundle is
    /// marked atomic by _markTgWellSpan at the end of the chain build. If the
    /// resulting region exceeds maxChunkPayloadBytes() the chunker fails
    /// loudly: restructure the epoch (e.g. bridge the full TG outflow and
    /// point withdrawWell elsewhere) or raise the budget.
    mapping(uint8 => uint256) private _tgWellSpanStart;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function name() external pure virtual override returns (string memory) {
        return "MIP Rewards Distribution";
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function initProposal(Addresses addresses) public override {
        // the etched mock precompiles (xcUSDT/xcUSDC/xcDOT) only exist on
        // Moonbeam, so the etching must run with the Moonbeam fork active
        // (the primary fork is now Ethereum)
        vm.selectFork(MOONBEAM_FORK_ID);
        etch(vm, addresses);

        string memory encodedJson = vm.readFile(
            vm.envString("MIP_REWARDS_PATH")
        );

        _parseTimestamps(encodedJson);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            vm.selectFork(networks[i].forkId);

            if (chainId == MOONBEAM_CHAIN_ID) {
                _saveMoonbeamDestinationActions(addresses, encodedJson);

                // save well balances before so we can validate the Moonbeam
                // destination transfers after execution
                IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));

                address unitroller = addresses.getAddress("UNITROLLER");
                wellBalancesBefore[unitroller] = well.balanceOf(unitroller);

                address moonbeamReserve = addresses.getAddress(
                    "ECOSYSTEM_RESERVE_PROXY"
                );
                wellBalancesBefore[moonbeamReserve] = well.balanceOf(
                    moonbeamReserve
                );

                // snapshot every transferFrom destination so the validation
                // step always has a before-balance to compare against
                for (
                    uint256 j = 0;
                    j < moonbeamActions.transferFroms.length;
                    j++
                ) {
                    address to = addresses.getAddress(
                        moonbeamActions.transferFroms[j].to
                    );
                    wellBalancesBefore[to] = well.balanceOf(to);
                }

                continue;
            }

            // every chain other than Moonbeam (including Ethereum, the
            // source chain) uses the external-chain JSON shape
            _saveExternalChainActions(addresses, encodedJson, chainId);

            // save well balances before
            IERC20 xwell = IERC20(addresses.getAddress("xWELL_PROXY"));
            address mrd = addresses.getAddress("MRD_PROXY");
            wellBalancesBefore[mrd] = xwell.balanceOf(mrd);

            if (addresses.isAddressSet("DEX_RELAYER")) {
                address dexRelayer = addresses.getAddress("DEX_RELAYER");
                wellBalancesBefore[dexRelayer] = xwell.balanceOf(dexRelayer);
            }

            if (addresses.isAddressSet("ECOSYSTEM_RESERVE_PROXY")) {
                address reserve = addresses.getAddress(
                    "ECOSYSTEM_RESERVE_PROXY"
                );
                wellBalancesBefore[reserve] = xwell.balanceOf(reserve);
            }

            if (chainId == ETHEREUM_CHAIN_ID) {
                // chain 1 is also the source chain: parse the bridge-outs
                // and snapshot the source-side xWELL balances
                _saveBridgeOuts(addresses, encodedJson);

                address governor = addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_V2_PROXY"
                );
                wellBalancesBefore[governor] = xwell.balanceOf(governor);

                if (addresses.isAddressSet("FOUNDATION_MULTISIG")) {
                    address foundation = addresses.getAddress(
                        "FOUNDATION_MULTISIG"
                    );
                    wellBalancesBefore[foundation] = xwell.balanceOf(
                        foundation
                    );
                }
            }

            // Save initial balances for reserve automation contracts
            JsonSpecExternalChain memory spec = externalChainActions[chainId];
            for (
                uint256 j = 0;
                j < spec.initSale.reserveAutomationContracts.length;
                j++
            ) {
                address reserveAutomationContract = addresses.getAddress(
                    spec.initSale.reserveAutomationContracts[j]
                );

                ReserveAutomation automation = ReserveAutomation(
                    reserveAutomationContract
                );
                address reserveAsset = automation.reserveAsset();

                reserveAutomationBalancesBefore[
                    reserveAutomationContract
                ] = IERC20(reserveAsset).balanceOf(reserveAutomationContract);
            }
        }

        vm.selectFork(ETHEREUM_FORK_ID);
    }

    function build(Addresses addresses) public virtual override {
        _buildMoonbeamDestinationActions(addresses);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _buildExternalChainActions(addresses, chainId);

                if (chainId == ETHEREUM_CHAIN_ID) {
                    _buildBridgeOutActions(addresses);
                }
            }
        }
    }

    function beforeSimulationHook(Addresses addresses) public virtual override {
        _validateSafetyModuleActions();

        vm.selectFork(ETHEREUM_FORK_ID);

        // Executor-fee funding for this epoch's bridges. Two modes:
        // - fee payer deployed ephemerally in deploy() (not yet canonical):
        //   deal() the fees so simulation works end-to-end.
        // - canonical instance from chains/1.json: assert its REAL balance
        //   covers the fees, mirroring the foundation allowance assertions —
        //   simulation must catch an unfunded fee payer before mainnet
        //   execution reverts with "FeePayer: insufficient fee balance".
        //   (Ops pre-funds it; anyone can send ETH; ~0.01 ETH covers ~150
        //   bridges at current quotes.)
        if (bridgeOuts.length > 0) {
            address feePayer = addresses.getAddress("xWELL_BRIDGE_FEE_PAYER");
            WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            uint256 totalBridgeCost = 0;
            for (uint256 i = 0; i < bridgeOuts.length; i++) {
                totalBridgeCost += adapter.bridgeCost(
                    bridgeOuts[i].network.toWormholeChainId()
                );
            }

            if (feePayer.balance < totalBridgeCost) {
                vm.deal(feePayer, totalBridgeCost);
            }
        }

        // The chain-1 transferFroms are executed by the governor as
        // token.transferFrom(FOUNDATION_MULTISIG, to, amount), which needs both
        // a balance and an allowance on the foundation Safe.
        //
        // BALANCE is asserted against real fork state and never mocked: the
        // treasury either holds the epoch's WELL or the proposal cannot execute,
        // and dealing it would hide that from the simulation.
        //
        // ALLOWANCE is a Safe transaction the foundation signs out-of-band,
        // shortly before execution and sized to the epoch. Requiring it to
        // already exist at authoring time would block every simulation until
        // ops signs, so the fork stands in for that approval when it is
        // missing — the same treatment the bridge fee payer gets above.
        // The approval is granted for exactly the epoch outflow, so a mocked
        // run still fails if the numbers grow past what ops will sign.
        {
            address foundation = addresses.getAddress("FOUNDATION_MULTISIG");
            address governor = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_V2_PROXY"
            );
            address xwell = addresses.getAddress("xWELL_PROXY");

            uint256 totalFoundationOutflow = 0;
            TransferFrom[] memory transferFroms = externalChainActions[
                ETHEREUM_CHAIN_ID
            ].transferFroms;
            for (uint256 i = 0; i < transferFroms.length; i++) {
                if (
                    addresses.getAddress(transferFroms[i].from) == foundation &&
                    addresses.getAddress(transferFroms[i].token) == xwell
                ) {
                    totalFoundationOutflow += transferFroms[i].amount;
                }
            }

            assertGe(
                IERC20(xwell).balanceOf(foundation),
                totalFoundationOutflow,
                "FOUNDATION_MULTISIG xWELL balance below epoch outflow"
            );
            uint256 currentAllowance = IERC20(xwell).allowance(
                foundation,
                governor
            );
            if (currentAllowance < totalFoundationOutflow) {
                console.log(
                    "WARNING: FOUNDATION_MULTISIG xWELL allowance to the governor is below the epoch outflow; simulating the approval Safe transaction."
                );
                console.log("  live allowance:", currentAllowance);
                console.log("  epoch outflow: ", totalFoundationOutflow);

                vm.prank(foundation);
                IERC20(xwell).approve(governor, totalFoundationOutflow);
            }
        }

        // Get the real on-chain Wormhole relayer to query actual bridge costs
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        IWormholeRelayer realRelayer = IWormholeRelayer(
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY")
        );

        // Query real on-chain bridge costs for all target chains
        uint16[] memory chainIds = new uint16[](3);
        uint256[] memory bridgeCosts = new uint256[](3);

        // Base - Wormhole Chain ID: 30
        chainIds[0] = 30;
        (bridgeCosts[0], ) = realRelayer.quoteEVMDeliveryPrice(
            chainIds[0],
            0,
            gasLimit
        );

        // Optimism - Wormhole Chain ID: 24
        chainIds[1] = 24;
        (bridgeCosts[1], ) = realRelayer.quoteEVMDeliveryPrice(
            chainIds[1],
            0,
            gasLimit
        );

        // Moonbeam - Wormhole Chain ID: 16
        chainIds[2] = 16;
        (bridgeCosts[2], ) = realRelayer.quoteEVMDeliveryPrice(
            chainIds[2],
            0,
            gasLimit
        );

        // mock relayer so we can simulate bridging well, initialized with real on-chain costs for all chains
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter(
            chainIds,
            bridgeCosts
        );
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        // we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
        // call it must switch forks
        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(ETHEREUM_WORMHOLE_CHAIN_ID);

        // encode gasLimit and relayer address since is stored in a single slot
        // relayer is first due to how evm pack values into a single storage
        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != ETHEREUM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);

                vm.store(
                    address(wormholeBridgeAdapter),
                    bytes32(uint256(153)),
                    encodedData
                );

                if (chainId == OPTIMISM_CHAIN_ID) {
                    (
                        ,
                        ,
                        uint256 periodFinish,
                        uint256 rewardRate,
                        ,

                    ) = IMultiRewards(
                            addresses.getAddress("USDC_MULTI_REWARDER")
                        ).rewardData(addresses.getAddress("xWELL_PROXY"));
                    leftoverRewardRate = rewardRate;
                    leftoverPeriodFinish = periodFinish;
                }
            }
        }

        vm.selectFork(primaryForkId());

        // stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        // Pre-fund cross-chain xWELL recipients.
        //
        // The V4+ WormholeBridgeAdapter uses wormhole.publishMessage +
        // executor execution requests instead of the deprecated relayer's
        // sendPayloadToEvm / receiveWormholeMessages path. The bridge-out
        // burns xWELL on Ethereum and relies on a VAA being executed on the
        // destination chain — which never happens in a forked simulation.
        // To keep rewards MIPs executable end-to-end, mint the bridged
        // amount directly on each destination so the downstream
        // transferFrom / merkle-campaign spend on TEMPORAL_GOVERNOR succeeds.
        {
            for (uint256 i = 0; i < bridgeOuts.length; i++) {
                uint256 destChain = bridgeOuts[i].network;
                if (destChain == ETHEREUM_CHAIN_ID) continue;

                vm.selectFork(destChain.toForkId());

                address xwell = addresses.getAddress("xWELL_PROXY");
                address recipient = addresses.getAddress(
                    bridgeOuts[i].target,
                    destChain
                );
                deal(
                    xwell,
                    recipient,
                    IERC20(xwell).balanceOf(recipient) + bridgeOuts[i].amount
                );
            }
        }

        vm.selectFork(ETHEREUM_FORK_ID);
    }

    function afterSimulationHook(Addresses addresses) public override {
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        bytes32 encodedData = bytes32(
            (uint256(
                uint160(addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"))
            ) << 96) | uint256(gasLimit)
        );

        vm.selectFork(chainId.toForkId());
        vm.store(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(primaryForkId());

        vm.store(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            bytes32(uint256(153)),
            encodedData
        );
    }

    function validate(Addresses addresses, address) public virtual override {
        _validateMoonbeamDestination(addresses);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _validateExternalChainActions(addresses, chainId);
            }
        }
    }

    /// -----------------------------------------------------
    /// -----------------------------------------------------
    /// -------------- Generic action batching --------------
    /// -----------------------------------------------------
    /// -----------------------------------------------------
    ///
    /// A full rewards epoch can encode to tens of KB across 100+ actions,
    /// which is far too large to submit in a single MultichainGovernorV2
    /// propose() call (propose() SSTOREs every action's calldata, so the
    /// binding limit is gas, not a protocol constant). The base
    /// HybridProposalV2 exposes three hooks for splitting the submission —
    /// chunkCount / chunkActions (split an oversized per-chain wormhole bundle
    /// across multiple VAAs) and batchProposeSplits (submit the proposal in
    /// several init + append propose() calls). Prior rewards MIPs (e.g. x59)
    /// hand-tuned these per JSON. This template computes them automatically
    /// from the encoded size of the actions, so future rewards MIPs inherit a
    /// submittable split with no manual boundary tuning.

    /// @notice max encoded byte size of a single chain's per-chunk temporal
    /// governor payload (one wormhole publishMessage governor action). A chain
    /// whose bundled actions exceed this is split into more chunks. Kept below
    /// maxProposeCallBytes() so any single chunk always fits in one propose()
    /// call. Virtual so a MIP can tune it without reimplementing the chunker.
    /// @dev this bounds payload BYTES, not execution gas on the destination
    /// chain: a byte-small chunk of gas-heavy actions can still exceed a
    /// destination per-tx cap (e.g. Moonbeam's 2^24 gas limit). Override with
    /// a lower budget when a chain's bundle is gas-dense.
    function maxChunkPayloadBytes() public view virtual returns (uint256) {
        return 11_000;
    }

    /// @notice max total calldata (bytes) of a single propose() submission.
    /// ~12KB keeps a submission comfortably under the Ethereum block gas limit
    /// given propose() stores every action's calldata. Virtual so a MIP can
    /// tune it without reimplementing the packer.
    function maxProposeCallBytes() public view virtual returns (uint256) {
        return 12_000;
    }

    /// @notice fixed per-call abi overhead accounted for when packing propose()
    /// calls: selector, the argument heads, array length words and the
    /// finalize bool. The init call's description is charged separately from
    /// its actual size in batchProposeSplits.
    uint256 private constant PROPOSE_CALL_OVERHEAD = 512;

    /// @notice number of wormhole publishMessage chunks a chain's bundle is
    /// split into. Size-driven: a chain whose actions encode within
    /// maxChunkPayloadBytes() rides a single VAA (return 1). Ethereum actions
    /// are local governor actions (never wormhole-bundled), so they are never
    /// chunked.
    /// @dev chunkCount and chunkActions share one partition computation and
    /// MUST be overridden together — overriding only one desynchronizes the
    /// chunk count from the slices and silently drops or duplicates actions.
    function chunkCount(
        ActionType actionType
    ) public view virtual override returns (uint256) {
        if (actionType == ActionType.Ethereum) {
            return 1;
        }

        ProposalAction[] memory a = getActionsByType(actionType);
        if (a.length == 0) {
            return 1;
        }

        return _computeChunkStarts(actionType, a).length;
    }

    /// @notice the actions belonging to chunk `index` of `actionType`,
    /// partitioned so each chunk encodes within maxChunkPayloadBytes() and no
    /// dependent action group straddles two chunks.
    /// @dev MUST be overridden together with chunkCount — see chunkCount.
    function chunkActions(
        ActionType actionType,
        uint256 index
    ) public view virtual override returns (ProposalAction[] memory) {
        if (actionType == ActionType.Ethereum) {
            return super.chunkActions(actionType, index);
        }

        ProposalAction[] memory a = getActionsByType(actionType);
        uint256[] memory starts = _computeChunkStarts(actionType, a);
        require(index < starts.length, "chunkActions: index out of range");

        uint256 start = starts[index];
        uint256 end = index + 1 < starts.length ? starts[index + 1] : a.length;

        return _sliceActions(a, start, end);
    }

    /// @notice governor-action indices at which the proposal is split into
    /// successive propose() calls, each within maxProposeCallBytes(). Greedily
    /// packs the ordered governor actions (every Ethereum action, then the
    /// Moonbeam / Base / Optimism chunks — matching getTargetsPayloadsValues
    /// order) into as few calls as fit. Empty => a single propose() call.
    function batchProposeSplits()
        public
        view
        virtual
        override
        returns (uint256[] memory)
    {
        uint256[] memory lens = _governorActionPayloadSizes();
        uint256 n = lens.length;

        uint256[] memory tmp = new uint256[](n);
        uint256 count = 0;
        uint256 budget = maxProposeCallBytes();

        // the init call additionally carries the proposal description —
        // ideally a short pinned IPFS URI, but the raw multi-KB markdown when
        // the pin has not happened yet — so its budget is charged with the
        // ACTUAL description size rather than assuming a short URI. Append
        // calls (propose(uint256,...)) carry no description and reset to the
        // fixed overhead.
        uint256 acc = PROPOSE_CALL_OVERHEAD +
            _roundUp32(bytes(_proposeDescription()).length);

        // an unpinned raw-markdown description can alone exceed the call
        // budget, making the init call unfixably oversized (no split can
        // shrink it). Warn loudly during simulation/printing so the author
        // pins the description to IPFS (descriptionUri) before submission.
        if (acc > budget) {
            console.log(
                "WARNING: proposal description alone exceeds maxProposeCallBytes; pin the description to IPFS (descriptionUri) before submission"
            );
        }

        for (uint256 i = 0; i < n; i++) {
            // per governor action in the propose() arrays: target (32) +
            // value (32) + payload offset (32) + payload length (32) + the
            // padded payload bytes
            uint256 contrib = 128 + _roundUp32(lens[i]);

            // a single governor action that cannot fit a propose() call even
            // alone can never be submitted within budget — fail loudly
            // instead of emitting an oversized call silently
            require(
                PROPOSE_CALL_OVERHEAD + contrib <= budget,
                "RewardsDistribution: single governor action exceeds maxProposeCallBytes"
            );

            if (i > 0 && acc + contrib > budget) {
                tmp[count++] = i;
                acc = PROPOSE_CALL_OVERHEAD;
            }

            acc += contrib;
        }

        uint256[] memory splits = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            splits[i] = tmp[i];
        }

        return splits;
    }

    /// @notice governor-action payload byte lengths in getTargetsPayloadsValues
    /// order: every Ethereum action individually, then one entry per chunk for
    /// Moonbeam, Base and Optimism (only for chains that have actions).
    function _governorActionPayloadSizes()
        private
        view
        returns (uint256[] memory lens)
    {
        lens = new uint256[](allActionTypesCount());
        uint256 idx = 0;

        ProposalAction[] memory eth = getActionsByType(ActionType.Ethereum);
        for (uint256 i = 0; i < eth.length; i++) {
            lens[idx++] = eth[i].data.length;
        }

        ActionType[3] memory bundled = [
            ActionType.Moonbeam,
            ActionType.Base,
            ActionType.Optimism
        ];
        for (uint256 b = 0; b < bundled.length; b++) {
            if (getActionsByType(bundled[b]).length == 0) {
                continue;
            }

            uint256 chunks = chunkCount(bundled[b]);
            for (uint256 c = 0; c < chunks; c++) {
                lens[idx++] = _chunkEncodedSize(chunkActions(bundled[b], c));
            }
        }
    }

    /// @notice minimum chunk start indices (per-type) that partition `a` so
    /// each chunk encodes within maxChunkPayloadBytes(), cutting only at safe
    /// boundaries (never inside a dependent action group). starts[0] == 0
    /// always; chunk k spans [starts[k], starts[k + 1]) with the last chunk
    /// running to a.length. Deterministic, so chunkCount and chunkActions agree.
    function _computeChunkStarts(
        ActionType actionType,
        ProposalAction[] memory a
    ) private view returns (uint256[] memory starts) {
        uint256 len = a.length;
        uint256[] memory tmp = new uint256[](len == 0 ? 1 : len);
        uint256 count = 0;
        tmp[count++] = 0;

        uint256 budget = maxChunkPayloadBytes();
        uint256 chunkStart = 0;
        uint256 prevBoundary = 0;

        for (uint256 b = 1; b <= len; b++) {
            // a cut before index b is allowed unless it splits a group; the
            // final boundary (b == len) is always allowed
            bool allowed = b == len || !_unsafeCut[uint8(actionType)][b];
            if (!allowed) {
                continue;
            }

            // if extending the current chunk to include the unit
            // [prevBoundary, b) overflows the budget, close the chunk at
            // prevBoundary and start a fresh one with this unit
            if (
                prevBoundary > chunkStart &&
                _chunkEncodedSize(_sliceActions(a, chunkStart, b)) > budget
            ) {
                tmp[count++] = prevBoundary;
                chunkStart = prevBoundary;
            }

            prevBoundary = b;
        }

        // an indivisible unit (atomic region or single action) larger than
        // the budget cannot be partitioned — fail loudly instead of silently
        // emitting an over-budget chunk that cascades into an over-budget
        // propose() call. Restructure the epoch (smaller atomic regions,
        // bridge the full TG outflow instead of relying on withdrawWell) or
        // raise maxChunkPayloadBytes().
        for (uint256 k = 0; k < count; k++) {
            require(
                _chunkEncodedSize(
                    _sliceActions(a, tmp[k], k + 1 < count ? tmp[k + 1] : len)
                ) <= budget,
                "RewardsDistribution: atomic action region exceeds maxChunkPayloadBytes"
            );
        }

        starts = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            starts[i] = tmp[i];
        }
    }

    /// @notice abi-encoded byte length of the wormhole publishMessage calldata
    /// that bundles `a` into one temporal governor VAA (the governor-action
    /// payload). The temporal governor address does not affect the encoded
    /// size, so a placeholder keeps this a pure size computation.
    function _chunkEncodedSize(
        ProposalAction[] memory a
    ) internal view returns (uint256) {
        address[] memory targets = new address[](a.length);
        uint256[] memory values = new uint256[](a.length);
        bytes[] memory payloads = new bytes[](a.length);

        for (uint256 i = 0; i < a.length; i++) {
            targets[i] = a[i].target;
            values[i] = a[i].value;
            payloads[i] = a[i].data;
        }

        return
            abi
                .encodeWithSignature(
                    "publishMessage(uint32,bytes,uint8)",
                    nonce,
                    abi.encode(address(1), targets, values, payloads),
                    consistencyLevel
                )
                .length;
    }

    function _sliceActions(
        ProposalAction[] memory a,
        uint256 start,
        uint256 end
    ) private pure returns (ProposalAction[] memory out) {
        out = new ProposalAction[](end - start);
        for (uint256 i = start; i < end; i++) {
            out[i - start] = a[i];
        }
    }

    function _roundUp32(uint256 x) private pure returns (uint256) {
        return ((x + 31) / 32) * 32;
    }

    function _actionTypeForChain(
        uint256 _chainId
    ) private pure returns (ActionType) {
        if (_chainId == MOONBEAM_CHAIN_ID) return ActionType.Moonbeam;
        if (_chainId == BASE_CHAIN_ID) return ActionType.Base;
        if (_chainId == OPTIMISM_CHAIN_ID) return ActionType.Optimism;
        return ActionType.Ethereum;
    }

    /// @notice mark the interior boundaries of a `groupLen`-action dependent
    /// sequence (starting at per-type index `start`) as forbidden chunk cut
    /// points, so the chunker keeps the whole group inside a single VAA.
    function _markAtomicGroup(
        ActionType actionType,
        uint256 start,
        uint256 groupLen
    ) internal {
        for (uint256 k = 1; k < groupLen; k++) {
            _unsafeCut[uint8(actionType)][start + k] = true;
        }
    }

    function _validateSafetyModuleActions() private view {
        // Check that no actions use the deprecated 'configureAsset' interface
        // and that no Base actions use 'configureAssets'
        for (uint256 i = 0; i < actions.length; i++) {
            bytes4 selector = bytes4(actions[i].data);
            bytes4 configureAssetSelector = bytes4(
                keccak256("configureAsset(uint128,address)")
            );

            require(
                selector != configureAssetSelector,
                string.concat(
                    "Action ",
                    vm.toString(i),
                    " uses deprecated configureAsset interface. Use configureAssets instead."
                )
            );

            bytes4 configureAssetsSelector = bytes4(
                keccak256("configureAssets(uint128[],uint256[],address[])")
            );

            // Base and Ethereum actions should not configure Safety Module assets
            if (
                actions[i].actionType == ActionType.Base ||
                actions[i].actionType == ActionType.Ethereum
            ) {
                require(
                    selector != configureAssetsSelector,
                    string.concat(
                        "Base/Ethereum action ",
                        vm.toString(i),
                        " uses configureAssets. Safety Module on Base/Ethereum should not be configured."
                    )
                );
            }
        }
    }

    /// @notice parse the ".1284" object. Moonbeam is now a pure destination
    /// chain in wind-down mode: comptroller reward speeds, safety module
    /// emissions, optional GOVTOKEN transfers and WELL withdrawals only.
    /// Parsed per-key for robustness (no whole-object decode).
    function _saveMoonbeamDestinationActions(
        Addresses addresses,
        string memory data
    ) private {
        string memory prefix = ".1284";

        // Once Moonbeam has no emissions left (wind-down), the reward
        // automation worker omits the 1284 block from its output entirely.
        // An absent block means "no Moonbeam destination actions": every
        // downstream consumer (build / validate) already iterates the empty
        // moonbeamActions arrays and guards stkWellEmissionsPerSecond on
        // `> 0`, so leaving the struct at its zero value is correct.
        if (!vm.keyExistsJson(data, prefix)) {
            return;
        }

        // stkWellEmissionsPerSecond
        uint256 stkWellEmissionsPerSecond = vm.parseJsonUint(
            data,
            string.concat(prefix, ".stkWellEmissionsPerSecond")
        );

        assertLe(
            stkWellEmissionsPerSecond,
            5e18,
            "stkWellEmissionsPerSecond must be less than 5e18"
        );

        moonbeamActions.stkWellEmissionsPerSecond = stkWellEmissionsPerSecond;

        // setRewardSpeed (comptroller shape)
        uint256 totalEpochRewards = 0;

        bytes memory setRewardSpeedBytes = vm.parseJson(
            data,
            string.concat(prefix, ".setRewardSpeed")
        );

        if (setRewardSpeedBytes.length > 0) {
            SetRewardSpeed[] memory setRewardSpeeds = abi.decode(
                setRewardSpeedBytes,
                (SetRewardSpeed[])
            );

            for (uint256 i = 0; i < setRewardSpeeds.length; i++) {
                SetRewardSpeed memory setRewardSpeed = setRewardSpeeds[i];

                // check for duplications
                for (
                    uint256 j = 0;
                    j < moonbeamActions.setRewardSpeed.length;
                    j++
                ) {
                    SetRewardSpeed
                        memory existingSetRewardSpeed = moonbeamActions
                            .setRewardSpeed[j];

                    require(
                        addresses.getAddress(existingSetRewardSpeed.market) !=
                            addresses.getAddress(setRewardSpeed.market) ||
                            existingSetRewardSpeed.rewardType !=
                            setRewardSpeed.rewardType,
                        "Duplication in setRewardSpeeds"
                    );
                }

                assertGe(
                    setRewardSpeed.newBorrowSpeed,
                    1,
                    "Borrow speed must be greater or equal to 1"
                );

                if (setRewardSpeed.rewardType == 0) {
                    assertLe(
                        setRewardSpeed.newSupplySpeed,
                        10e18,
                        "Supply speed must be less than 10 WELL per second"
                    );

                    uint256 supplyAmount = uint256(
                        setRewardSpeed.newSupplySpeed
                    ) * (endTimeStamp - startTimeStamp);

                    uint256 borrowAmount = uint256(
                        setRewardSpeed.newBorrowSpeed
                    ) * (endTimeStamp - startTimeStamp);

                    totalEpochRewards += supplyAmount + borrowAmount;
                }

                moonbeamActions.setRewardSpeed.push(setRewardSpeed);
            }
        }

        // transferFrom (GOVTOKEN moves executed by the TemporalGovernor)
        bytes memory transferFromBytes = vm.parseJson(
            data,
            string.concat(prefix, ".transferFrom")
        );

        if (transferFromBytes.length > 0) {
            TransferFrom[] memory transferFroms = abi.decode(
                transferFromBytes,
                (TransferFrom[])
            );

            for (uint256 i = 0; i < transferFroms.length; i++) {
                require(
                    keccak256(abi.encodePacked(transferFroms[i].to)) !=
                        keccak256("COMPTROLLER"),
                    "should not transfer funds to COMPTROLLER logic contract"
                );

                _validateTransferDestination(transferFroms[i].to);

                if (
                    addresses.getAddress(transferFroms[i].to) ==
                    addresses.getAddress("UNITROLLER")
                ) {
                    assertApproxEqRel(
                        transferFroms[i].amount,
                        totalEpochRewards,
                        0.01e18,
                        "Transfer amount must be close to the total rewards for the epoch"
                    );
                }

                if (
                    addresses.getAddress(transferFroms[i].to) ==
                    addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
                ) {
                    assertApproxEqRel(
                        transferFroms[i].amount,
                        moonbeamActions.stkWellEmissionsPerSecond *
                            (endTimeStamp - startTimeStamp),
                        0.1e18,
                        "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
                    );
                }

                moonbeamActions.transferFroms.push(transferFroms[i]);
            }
        }

        // withdrawWell
        bytes memory withdrawWellBytes = vm.parseJson(
            data,
            string.concat(prefix, ".withdrawWell")
        );

        if (withdrawWellBytes.length > 0) {
            WithdrawWell[] memory withdrawWells = abi.decode(
                withdrawWellBytes,
                (WithdrawWell[])
            );

            for (uint256 i = 0; i < withdrawWells.length; i++) {
                _validateTransferDestination(withdrawWells[i].to);

                moonbeamActions.withdrawWell.push(withdrawWells[i]);
            }
        }
    }

    /// @notice parse the ".1.bridgeToRecipient" array — xWELL bridged out
    /// from Ethereum (the source chain) by the governor via the
    /// WormholeBridgeAdapter on-chain-quoted path.
    /// @dev must run after _saveExternalChainActions(.., ETHEREUM_CHAIN_ID)
    /// so the governor top-up cross-check below sees the parsed transferFroms
    function _saveBridgeOuts(Addresses addresses, string memory data) private {
        bytes memory bridgeOutBytes = vm.parseJson(
            data,
            ".1.bridgeToRecipient"
        );

        if (bridgeOutBytes.length == 0) {
            return;
        }

        BridgeOut[] memory parsedBridgeOuts = abi.decode(
            bridgeOutBytes,
            (BridgeOut[])
        );

        uint256 totalBridgedOut = 0;

        for (uint256 i = 0; i < parsedBridgeOuts.length; i++) {
            require(
                parsedBridgeOuts[i].network != ETHEREUM_CHAIN_ID,
                "BridgeOut: cannot bridge to the source chain"
            );

            require(
                parsedBridgeOuts[i].amount > 0,
                "BridgeOut: amount must be greater than 0"
            );

            totalBridgedOut += parsedBridgeOuts[i].amount;

            bridgeOuts.push(parsedBridgeOuts[i]);
        }

        // the governor only holds xWELL to bridge it out; the amount
        // transferred from the foundation to the governor must match the
        // total bridged out
        uint256 totalGovernorTopUp = 0;
        TransferFrom[] memory transferFroms = externalChainActions[
            ETHEREUM_CHAIN_ID
        ].transferFroms;
        for (uint256 i = 0; i < transferFroms.length; i++) {
            if (
                addresses.getAddress(transferFroms[i].to) ==
                addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
            ) {
                totalGovernorTopUp += transferFroms[i].amount;
            }
        }

        assertEq(
            totalGovernorTopUp,
            totalBridgedOut,
            "BridgeOut: governor top-up must match total bridged out"
        );
    }

    function _saveStkWellEmissionsPerSecond(
        string memory data,
        string memory prefix,
        uint256 _chainId
    ) private {
        require(
            _chainId != BASE_CHAIN_ID && _chainId != ETHEREUM_CHAIN_ID,
            "Safety Module on Base/Ethereum should not be configured"
        );

        uint256 stkWellEmissionsPerSecond = vm.parseJsonUint(
            data,
            string.concat(prefix, ".stkWellEmissionsPerSecond")
        );

        assertLe(
            stkWellEmissionsPerSecond,
            10e18,
            "stkWellEmissionsPerSecond must be less than 10e18"
        );

        externalChainActions[_chainId]
            .stkWellEmissionsPerSecond = stkWellEmissionsPerSecond;
    }

    function _saveMRDEmissionSpeeds(
        Addresses addresses,
        string memory data,
        string memory prefix,
        uint256 _chainId
    )
        private
        returns (uint256 totalWellEpochRewards, uint256 totalOpEpochRewards)
    {
        // save MRD emission speeds for markets
        bytes memory setRewardSpeedsBytes = vm.parseJson(
            data,
            string.concat(prefix, ".setMRDSpeeds")
        );
        SetMRDRewardSpeed[] memory setRewardSpeeds = abi.decode(
            setRewardSpeedsBytes,
            (SetMRDRewardSpeed[])
        );

        for (uint256 i = 0; i < setRewardSpeeds.length; i++) {
            // check for duplications
            for (
                uint256 j = 0;
                j < externalChainActions[_chainId].setRewardSpeed.length;
                j++
            ) {
                SetMRDRewardSpeed
                    memory existingSetRewardSpeed = externalChainActions[
                        _chainId
                    ].setRewardSpeed[j];

                require(
                    addresses.getAddress(existingSetRewardSpeed.market) !=
                        addresses.getAddress(setRewardSpeeds[i].market) ||
                        addresses.getAddress(
                            existingSetRewardSpeed.emissionToken
                        ) !=
                        addresses.getAddress(setRewardSpeeds[i].emissionToken),
                    "Duplication in setRewardSpeeds"
                );
            }

            // save MRD emission speeds for markets
            int256 supplySpeed = setRewardSpeeds[i].newSupplySpeed;
            int256 borrowSpeed = setRewardSpeeds[i].newBorrowSpeed;

            // check borrow speed
            if (borrowSpeed != -1) {
                assertGe(
                    borrowSpeed,
                    1,
                    "Borrow speed must be greater or equal to 1"
                );
            }

            // save end time
            uint256 endTime = uint256(setRewardSpeeds[i].newEndTime);

            // when token is xWELL
            if (
                addresses.getAddress(setRewardSpeeds[i].emissionToken) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                // check supply speed
                assertLe(
                    supplySpeed,
                    10e18,
                    "Supply speed must be less than 10 WELL per second"
                );

                // calculate supply amount
                uint256 supplyAmount = supplySpeed != int256(-1)
                    ? uint256(supplySpeed) * (endTime - startTimeStamp)
                    : 0;

                // calculate borrow amount
                uint256 borrowAmount = borrowSpeed != int256(-1)
                    ? (uint256(borrowSpeed) * (endTime - startTimeStamp))
                    : 0;

                // add to total well epoch rewards
                totalWellEpochRewards += supplyAmount + borrowAmount;
            }

            // when token is OP
            if (
                chainId == OPTIMISM_CHAIN_ID &&
                addresses.getAddress(setRewardSpeeds[i].emissionToken) ==
                addresses.getAddress("OP", OPTIMISM_CHAIN_ID)
            ) {
                // calculate supply amount
                uint256 supplyAmount = supplySpeed != int256(-1)
                    ? uint256(supplySpeed) * (endTime - startTimeStamp)
                    : 0;

                // calculate borrow amount
                uint256 borrowAmount = borrowSpeed != int256(-1)
                    ? (uint256(borrowSpeed) * (endTime - startTimeStamp))
                    : 0;

                // add to total op epoch rewards
                totalOpEpochRewards += supplyAmount + borrowAmount;
            }

            externalChainActions[_chainId].setRewardSpeed.push(
                setRewardSpeeds[i]
            );
        }
    }

    function _saveTransferFroms(
        Addresses addresses,
        string memory data,
        string memory prefix,
        uint256 _chainId,
        uint256 totalWellEpochRewards,
        uint256 totalOpEpochRewards
    ) private returns (uint256 ecosystemReserveProxyAmount) {
        bytes memory transferFromsBytes = vm.parseJson(
            data,
            string.concat(prefix, ".transferFrom")
        );
        TransferFrom[] memory transferFroms = abi.decode(
            transferFromsBytes,
            (TransferFrom[])
        );

        for (uint256 i = 0; i < transferFroms.length; i++) {
            // xWELL top-up of the MRD must match the epoch rewards and
            // come from the chain's expected funding source
            // (FOUNDATION_MULTISIG on Ethereum, TEMPORAL_GOVERNOR on Base
            // and Optimism).
            if (
                addresses.getAddress(transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY") &&
                addresses.getAddress(transferFroms[i].token) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                assertEq(
                    addresses.getAddress(transferFroms[i].from),
                    _chainId == ETHEREUM_CHAIN_ID
                        ? addresses.getAddress(
                            "FOUNDATION_MULTISIG",
                            ETHEREUM_CHAIN_ID
                        )
                        : addresses.getAddress("TEMPORAL_GOVERNOR", _chainId),
                    "MRD xWELL top-up from unexpected source"
                );
                assertApproxEqRel(
                    transferFroms[i].amount,
                    totalWellEpochRewards,
                    0.1e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            // check OP
            if (
                chainId == OPTIMISM_CHAIN_ID &&
                addresses.getAddress(transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY") &&
                addresses.getAddress(transferFroms[i].from) ==
                addresses.getAddress(
                    "FOUNDATION_OP_MULTISIG",
                    OPTIMISM_CHAIN_ID
                ) &&
                addresses.getAddress(transferFroms[i].token) ==
                addresses.getAddress("OP", OPTIMISM_CHAIN_ID)
            ) {
                assertApproxEqRel(
                    transferFroms[i].amount,
                    totalOpEpochRewards,
                    0.01e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            // check for duplications
            for (uint256 j = 0; j < transferFroms.length; j++) {
                TransferFrom memory existingTransferFrom = transferFroms[j];

                _validateTransferDestination(existingTransferFrom.to);
            }

            if (
                addresses.getAddress(transferFroms[i].to) ==
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
            ) {
                ecosystemReserveProxyAmount += transferFroms[i].amount;
            }

            externalChainActions[_chainId].transferFroms.push(transferFroms[i]);
        }
    }

    function _saveWithdrawWell(
        Addresses addresses,
        string memory data,
        string memory prefix,
        uint256 _chainId
    ) private returns (uint256 ecosystemReserveProxyAmount) {
        bytes memory withdrawWellsBytes = vm.parseJson(
            data,
            string.concat(prefix, ".withdrawWell")
        );
        WithdrawWell[] memory withdrawWells = abi.decode(
            withdrawWellsBytes,
            (WithdrawWell[])
        );

        for (uint256 i = 0; i < withdrawWells.length; i++) {
            WithdrawWell memory withdrawWell = withdrawWells[i];

            _validateTransferDestination(withdrawWell.to);

            if (
                addresses.getAddress(withdrawWell.to) ==
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
            ) {
                ecosystemReserveProxyAmount += withdrawWell.amount;
            }

            externalChainActions[_chainId].withdrawWell.push(withdrawWell);
        }

        return ecosystemReserveProxyAmount;
    }

    function _saveMekleCampaigns(
        string memory data,
        string memory prefix,
        uint256 _chainId
    ) private {
        bytes memory mekleCampaignsBytes = vm.parseJson(
            data,
            string.concat(prefix, ".merkleCampaigns")
        );
        if (mekleCampaignsBytes.length == 0) {
            return;
        }
        MekleCampaign[] memory merkleCampaigns = abi.decode(
            mekleCampaignsBytes,
            (MekleCampaign[])
        );

        for (uint256 i = 0; i < merkleCampaigns.length; i++) {
            MekleCampaign memory campaign = merkleCampaigns[i];

            // Validate campaign parameters
            require(
                campaign.amount > 0,
                "MekleCampaign: amount must be greater than 0"
            );

            require(
                campaign.duration > 0,
                "MekleCampaign: duration must be greater than 0"
            );

            require(
                bytes(campaign.rewardToken).length > 0,
                "MekleCampaign: reward token cannot be empty"
            );

            //     require(
            //         campaign.startTimestamp > block.timestamp,
            //         "MekleCampaign: start timestamp must be in the future"
            //     );

            externalChainActions[_chainId].merkleCampaigns.push(campaign);
        }
    }

    function _saveExternalChainActions(
        Addresses addresses,
        string memory data,
        uint256 _chainId
    ) private {
        string memory prefix = string.concat(".", vm.toString(_chainId));

        // no Safety Module on Base; the "1" object carries no
        // stkWellEmissionsPerSecond key either (no stkWELL incentives
        // configured from the source chain object)
        if (_chainId != BASE_CHAIN_ID && _chainId != ETHEREUM_CHAIN_ID) {
            _saveStkWellEmissionsPerSecond(data, prefix, _chainId);
        }

        (
            uint256 totalWellEpochRewards,
            uint256 totalOpEpochRewards
        ) = _saveMRDEmissionSpeeds(addresses, data, prefix, _chainId);

        uint256 ecosystemReserveProxyAmount = _saveTransferFroms(
            addresses,
            data,
            prefix,
            _chainId,
            totalWellEpochRewards,
            totalOpEpochRewards
        );

        ecosystemReserveProxyAmount =
            ecosystemReserveProxyAmount +
            _saveWithdrawWell(addresses, data, prefix, _chainId);

        if (_chainId != BASE_CHAIN_ID && _chainId != ETHEREUM_CHAIN_ID) {
            assertApproxEqRel(
                ecosystemReserveProxyAmount,
                (externalChainActions[_chainId].stkWellEmissionsPerSecond *
                    (endTimeStamp - startTimeStamp)),
                1e18,
                "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
            );
        }

        bytes memory transferReservesBytes = vm.parseJson(
            data,
            string.concat(prefix, ".transferReserves")
        );

        if (transferReservesBytes.length > 0) {
            TransferReserves[] memory transferReserves = abi.decode(
                transferReservesBytes,
                (TransferReserves[])
            );

            for (uint256 i = 0; i < transferReserves.length; i++) {
                TransferReserves memory transferReserve = transferReserves[i];

                externalChainActions[_chainId].transferReserves.push(
                    transferReserve
                );
            }
        }

        {
            bytes memory initSaleBytes = vm.parseJson(
                data,
                string.concat(prefix, ".initSale")
            );

            if (initSaleBytes.length > 0) {
                InitSale memory initSale = abi.decode(
                    initSaleBytes,
                    (InitSale)
                );

                // Process initSale if it exists in the JSON and has valid data
                if (
                    initSale.auctionPeriod != 0 ||
                    initSale.reserveAutomationContracts.length > 0
                ) {
                    for (
                        uint256 i = 0;
                        i < initSale.reserveAutomationContracts.length;
                        i++
                    ) {
                        // Get the ReserveAutomation contract and its reserveAsset
                        address reserveAutomationContract = addresses
                            .getAddress(initSale.reserveAutomationContracts[i]);

                        // Sanity check: delay must be less than or equal to MAXIMUM_AUCTION_DELAY
                        assertLe(
                            initSale.delay,
                            ReserveAutomation(reserveAutomationContract)
                                .MAXIMUM_AUCTION_DELAY(),
                            "RewardsDistribution: delay exceeds MAXIMUM_AUCTION_DELAY"
                        );

                        // Sanity check: maxDiscount must be less than SCALAR (1e18)
                        assertLt(
                            initSale.periodMaxDiscount,
                            ReserveAutomation(reserveAutomationContract)
                                .SCALAR(),
                            "RewardsDistribution: periodMaxDiscount must be less than SCALAR"
                        );

                        // Sanity check: startingPremium must be greater than SCALAR (1e18)
                        assertGt(
                            uint256(initSale.periodStartingPremium),
                            ReserveAutomation(reserveAutomationContract)
                                .SCALAR(),
                            "RewardsDistribution: periodStartingPremium must be greater than SCALAR"
                        );

                        // Sanity check: auctionPeriod must be perfectly divisible by miniAuctionPeriod
                        assertEq(
                            initSale.auctionPeriod % initSale.miniAuctionPeriod,
                            0,
                            "RewardsDistribution: auctionPeriod must be perfectly divisible by miniAuctionPeriod"
                        );

                        // Sanity check: must have more than one mini-auction
                        assertGt(
                            initSale.auctionPeriod / initSale.miniAuctionPeriod,
                            1,
                            "RewardsDistribution: must have more than one mini-auction"
                        );

                        // Sanity check: miniAuctionPeriod must be greater than 1
                        assertGt(
                            initSale.miniAuctionPeriod,
                            10000,
                            "RewardsDistribution: miniAuctionPeriod must be greater than 10000"
                        );
                    }

                    externalChainActions[_chainId].initSale = initSale;
                }
            }
        }

        _saveMekleCampaigns(data, prefix, _chainId);
        _processMultiRewarder(data, prefix, _chainId);
    }

    function _processMultiRewarder(
        string memory data,
        string memory prefix,
        uint256 _chainId
    ) private {
        bytes memory multiRewarderBytes = vm.parseJson(
            data,
            string.concat(prefix, ".multiRewarder")
        );
        if (multiRewarderBytes.length == 0) {
            return;
        }
        MultiRewarder[] memory multiRewarders = abi.decode(
            multiRewarderBytes,
            (MultiRewarder[])
        );

        for (uint256 i = 0; i < multiRewarders.length; i++) {
            MultiRewarder memory multiRewarder = multiRewarders[i];

            // safety check duration is 4 weeks
            assertEq(
                multiRewarder.duration,
                2419200,
                "MultiRewarder: duration must be 4 weeks"
            );

            externalChainActions[_chainId].multiRewarder.push(multiRewarder);
        }
    }

    function _buildMoonbeamDestinationActions(Addresses addresses) private {
        vm.selectFork(MOONBEAM_FORK_ID);

        JsonSpecMoonbeam memory spec = moonbeamActions;
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address token = addresses.getAddress(transferFrom.token);
            address from = addresses.getAddress(transferFrom.from);
            address to = addresses.getAddress(transferFrom.to);

            // the TemporalGovernor is the executor on Moonbeam; transfers
            // out of it are plain transfers, anything else needs a prior
            // approval and is executed as transferFrom
            if (from == addresses.getAddress("TEMPORAL_GOVERNOR")) {
                _pushAction(
                    token,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        to,
                        transferFrom.amount
                    ),
                    string.concat(
                        "Transfer token ",
                        vm.getLabel(token),
                        " from ",
                        vm.getLabel(from),
                        " to ",
                        vm.getLabel(to),
                        " amount ",
                        vm.toString(transferFrom.amount / 1e18),
                        " on Moonbeam"
                    ),
                    ActionType.Moonbeam
                );
            } else {
                _pushAction(
                    token,
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)",
                        from,
                        to,
                        transferFrom.amount
                    ),
                    string.concat(
                        "Transfer token ",
                        vm.getLabel(token),
                        " from ",
                        vm.getLabel(from),
                        " to ",
                        vm.getLabel(to),
                        " amount ",
                        vm.toString(transferFrom.amount / 1e18),
                        " on Moonbeam"
                    ),
                    ActionType.Moonbeam
                );
            }
        }

        // withdraw WELL from the Market Reserve ERC20 Holding Deposit contract
        // (the active fork is Moonbeam, so the 3-arg _pushAction inside the
        // helper resolves to ActionType.Moonbeam)
        _buildWithdrawWellActions(
            addresses,
            MOONBEAM_CHAIN_ID,
            spec.withdrawWell,
            "GOVTOKEN"
        );

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];
            assertGe(
                setRewardSpeed.newBorrowSpeed,
                1,
                "Borrow speed must be greater or equal to 1"
            );

            _pushAction(
                addresses.getAddress("UNITROLLER"),
                abi.encodeWithSignature(
                    "_setRewardSpeed(uint8,address,uint256,uint256)",
                    uint8(setRewardSpeed.rewardType),
                    addresses.getAddress(setRewardSpeed.market),
                    setRewardSpeed.newSupplySpeed.toUint256(),
                    setRewardSpeed.newBorrowSpeed.toUint256()
                ),
                string.concat(
                    "Set reward speed for market ",
                    vm.getLabel(addresses.getAddress(setRewardSpeed.market)),
                    " on Moonbeam.\nSupply speed: ",
                    vm.toString(setRewardSpeed.newSupplySpeed),
                    "\nBorrow speed: ",
                    vm.toString(setRewardSpeed.newBorrowSpeed),
                    "\nReward type: ",
                    vm.toString(setRewardSpeed.rewardType)
                ),
                ActionType.Moonbeam
            );
        }

        if (spec.stkWellEmissionsPerSecond > 0) {
            address safetyModule = addresses.getAddress("STK_GOVTOKEN_PROXY");
            uint128[] memory emissionPerSecond = new uint128[](1);
            emissionPerSecond[0] = spec.stkWellEmissionsPerSecond.toUint128();
            uint256[] memory totalStaked = new uint256[](1);
            totalStaked[0] = 0;
            address[] memory underlyingAsset = new address[](1);
            underlyingAsset[0] = safetyModule;

            _pushAction(
                safetyModule,
                abi.encodeWithSignature(
                    "configureAssets(uint128[],uint256[],address[])",
                    emissionPerSecond,
                    totalStaked,
                    underlyingAsset
                ),
                string.concat(
                    "Set reward speed for the Safety Module on Moonbeam.\nEmissions per second: ",
                    vm.toString(spec.stkWellEmissionsPerSecond)
                ),
                ActionType.Moonbeam
            );
        }

        // must run after every Moonbeam action has been pushed (see
        // _tgWellSpanStart)
        _markTgWellSpan(MOONBEAM_CHAIN_ID);
    }

    function _buildExternalChainActions(
        Addresses addresses,
        uint256 _chainId
    ) private {
        vm.selectFork(_chainId.toForkId());

        JsonSpecExternalChain memory spec = externalChainActions[_chainId];

        // the proposal executor on this chain: actions run as the
        // MultichainGovernorV2 on Ethereum (the governance hub) and as the
        // TemporalGovernor on every other chain
        address proposalExecutor = _chainId == ETHEREUM_CHAIN_ID
            ? addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
            : addresses.getAddress("TEMPORAL_GOVERNOR");

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address token = addresses.getAddress(transferFrom.token);
            address from = addresses.getAddress(transferFrom.from);
            address to = addresses.getAddress(transferFrom.to);

            // transfers out of the executor itself are plain transfers;
            // anything else (e.g. FOUNDATION_MULTISIG on Ethereum) requires
            // a prior approval to the executor and uses transferFrom
            if (from != proposalExecutor) {
                _pushAction(
                    token,
                    abi.encodeWithSignature(
                        "transferFrom(address,address,uint256)",
                        from,
                        to,
                        transferFrom.amount
                    ),
                    string.concat(
                        "Transfer token ",
                        vm.getLabel(token),
                        " from ",
                        vm.getLabel(from),
                        " to ",
                        vm.getLabel(to),
                        " amount ",
                        vm.toString(transferFrom.amount / 1e18),
                        " on ",
                        _chainId.chainIdToName()
                    )
                );
            } else {
                _pushAction(
                    token,
                    abi.encodeWithSignature(
                        "transfer(address,uint256)",
                        to,
                        transferFrom.amount
                    ),
                    string.concat(
                        "Transfer token ",
                        vm.getLabel(token),
                        " from ",
                        vm.getLabel(from),
                        " to ",
                        vm.getLabel(to),
                        " amount ",
                        vm.toString(transferFrom.amount / 1e18),
                        " on ",
                        _chainId.chainIdToName()
                    )
                );
            }
        }

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetMRDRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);
            address mrd = addresses.getAddress("MRD_PROXY");

            // only update if the configuration exists
            if (setRewardSpeed.newSupplySpeed != -1) {
                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_updateSupplySpeed(address,address,uint256)",
                        addresses.getAddress(setRewardSpeed.market),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        setRewardSpeed.newSupplySpeed.toUint256()
                    ),
                    string.concat(
                        "Set reward supply speed to ",
                        vm.toString(setRewardSpeed.newSupplySpeed),
                        " for ",
                        vm.getLabel(market),
                        ".\nNetwork: ",
                        _chainId.chainIdToName(),
                        "\nReward token: ",
                        setRewardSpeed.emissionToken
                    )
                );
            }

            if (setRewardSpeed.newBorrowSpeed != -1) {
                assertGe(
                    setRewardSpeed.newBorrowSpeed,
                    1,
                    "Borrow speed must be greater or equal to 1"
                );

                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_updateBorrowSpeed(address,address,uint256)",
                        addresses.getAddress(setRewardSpeed.market),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        setRewardSpeed.newBorrowSpeed.toUint256()
                    ),
                    string.concat(
                        "Set reward borrow speed to ",
                        vm.toString(setRewardSpeed.newBorrowSpeed),
                        " for ",
                        vm.getLabel(market),
                        ".\nNetwork: ",
                        _chainId.chainIdToName(),
                        "\nReward token: ",
                        setRewardSpeed.emissionToken
                    )
                );
            }

            if (setRewardSpeed.newEndTime != -1) {
                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_updateEndTime(address,address,uint256)",
                        addresses.getAddress(setRewardSpeed.market),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        setRewardSpeed.newEndTime
                    ),
                    string.concat(
                        "Set reward end time to ",
                        vm.toString(setRewardSpeed.newEndTime),
                        " for ",
                        vm.getLabel(market),
                        ".\nNetwork:",
                        _chainId.chainIdToName(),
                        "\nReward token: ",
                        setRewardSpeed.emissionToken
                    )
                );
            }
        }

        if (spec.stkWellEmissionsPerSecond > 0) {
            address safetyModule = addresses.getAddress("STK_GOVTOKEN_PROXY");
            uint128[] memory emissionPerSecond = new uint128[](1);
            emissionPerSecond[0] = spec.stkWellEmissionsPerSecond.toUint128();
            uint256[] memory totalStaked = new uint256[](1);
            totalStaked[0] = 0;
            address[] memory underlyingAsset = new address[](1);
            underlyingAsset[0] = safetyModule;

            _pushAction(
                safetyModule,
                abi.encodeWithSignature(
                    "configureAssets(uint128[],uint256[],address[])",
                    emissionPerSecond,
                    totalStaked,
                    underlyingAsset
                ),
                string.concat(
                    "Set reward speed to ",
                    vm.toString(spec.stkWellEmissionsPerSecond),
                    " for the Safety Module on ",
                    _chainId.chainIdToName()
                )
            );
        }

        _buildReserveAutomationActions(
            addresses,
            _chainId,
            spec.transferReserves,
            spec.initSale
        );

        // withdraw WELL from the Market Reserve ERC20 Holding Deposit
        // contract. Built AFTER the reserve automation region on purpose:
        // the TG-WELL atomic span runs from the first withdrawWell(to = TG)
        // to the end of the bundle, and the reserve region never touches TG
        // WELL — building it first keeps it out of the span, so the span
        // only covers the WELL-spending multiRewarder/merkle actions and
        // stays well under the chunk budget.
        _buildWithdrawWellActions(
            addresses,
            _chainId,
            spec.withdrawWell,
            "xWELL_PROXY"
        );

        _buildMultiRewarderActions(addresses, _chainId, spec.multiRewarder);

        _buildMerkleCampaignActions(addresses, _chainId, spec.merkleCampaigns);

        // must run after every action of this chain has been pushed: marks
        // the span from the first withdrawWell(to = TEMPORAL_GOVERNOR) to the
        // end of the bundle as atomic (see _tgWellSpanStart)
        _markTgWellSpan(_chainId);
    }

    /// @notice build the reserve automation actions for a chain laid out PER
    /// MARKET: each market's reduce -> transfer pair is immediately followed
    /// by the initiateSale of the automation contract it funds, and the
    /// 2-or-3-action group is marked atomic. initiateSale computes
    /// periodSaleAmount from the automation contract's reserveAsset balance
    /// AT EXECUTION TIME (and reverts when it is zero), while chunks execute
    /// as independent temporal governor proposals with no ordering guarantee
    /// — so a market's funding and its sale must ride a single VAA. The
    /// per-market layout keeps each atomic group small, letting the chunker
    /// cut BETWEEN markets instead of carrying one indivisible region that
    /// grows with the market count. initiateSale calls for contracts not
    /// funded by this epoch's transferReserves (selling a pre-existing
    /// balance) are appended afterwards as independent single actions.
    function _buildReserveAutomationActions(
        Addresses addresses,
        uint256 _chainId,
        TransferReserves[] memory transferReserves,
        InitSale memory initSale
    ) private {
        ActionType t = _actionTypeForChain(_chainId);

        // whether this epoch initiates sales at all (same validity condition
        // the JSON parser uses)
        bool hasSales = initSale.auctionPeriod != 0 ||
            initSale.reserveAutomationContracts.length > 0;

        bool[] memory saleBuilt = new bool[](
            initSale.reserveAutomationContracts.length
        );

        for (uint256 i = 0; i < transferReserves.length; i++) {
            uint256 grpStart = actions.proposalActionTypeCount(t);

            IERC20 underlying = IERC20(
                MErc20(addresses.getAddress(transferReserves[i].market))
                    .underlying()
            );

            _pushAction(
                addresses.getAddress(transferReserves[i].market),
                abi.encodeWithSignature(
                    "_reduceReserves(uint256)",
                    transferReserves[i].amount
                ),
                string.concat(
                    "Withdraw ",
                    vm.toString(
                        transferReserves[i].amount / underlying.decimals()
                    ),
                    " ",
                    underlying.symbol(),
                    " from ",
                    transferReserves[i].market,
                    " on ",
                    _chainId.chainIdToName()
                )
            );

            _pushAction(
                address(underlying),
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    addresses.getAddress(transferReserves[i].to),
                    transferReserves[i].amount
                ),
                string.concat(
                    "Transfer ",
                    vm.toString(
                        transferReserves[i].amount / underlying.decimals()
                    ),
                    " ",
                    underlying.symbol(),
                    " to ",
                    transferReserves[i].to,
                    " on ",
                    _chainId.chainIdToName()
                )
            );

            // the initiateSale of the automation contract this transfer
            // funds joins the market's atomic group
            if (hasSales) {
                for (
                    uint256 j = 0;
                    j < initSale.reserveAutomationContracts.length;
                    j++
                ) {
                    if (
                        addresses.getAddress(
                            initSale.reserveAutomationContracts[j]
                        ) == addresses.getAddress(transferReserves[i].to)
                    ) {
                        // a second transferReserves funding the same
                        // automation contract would leave the already-built
                        // initiateSale sized without it (the sale snapshots
                        // its balance at execution time) — fail loudly. The
                        // worker emits exactly one transferReserves per
                        // market; merge the amounts if that ever changes.
                        require(
                            !saleBuilt[j],
                            "RewardsDistribution: multiple transferReserves fund one automation contract"
                        );
                        saleBuilt[j] = true;
                        _pushInitiateSale(addresses, _chainId, initSale, j);
                    }
                }
            }

            _markAtomicGroup(
                t,
                grpStart,
                actions.proposalActionTypeCount(t) - grpStart
            );
        }

        // sales of pre-existing balances (no transferReserves funding this
        // epoch): independent single actions, safe to cut around
        if (hasSales) {
            for (
                uint256 j = 0;
                j < initSale.reserveAutomationContracts.length;
                j++
            ) {
                if (!saleBuilt[j]) {
                    _pushInitiateSale(addresses, _chainId, initSale, j);
                }
            }
        }
    }

    /// @notice push a single initiateSale action for the automation contract
    /// at `index` of initSale.reserveAutomationContracts
    function _pushInitiateSale(
        Addresses addresses,
        uint256 _chainId,
        InitSale memory initSale,
        uint256 index
    ) private {
        address reserveAutomationContract = addresses.getAddress(
            initSale.reserveAutomationContracts[index]
        );

        _pushAction(
            reserveAutomationContract,
            abi.encodeWithSignature(
                "initiateSale(uint256,uint256,uint256,uint256,uint256)",
                initSale.delay,
                initSale.auctionPeriod,
                initSale.miniAuctionPeriod,
                initSale.periodMaxDiscount,
                initSale.periodStartingPremium
            ),
            string.concat(
                "Init reserve sale for ",
                vm.getLabel(reserveAutomationContract),
                " on ",
                _chainId.chainIdToName()
            )
        );
    }

    /// @notice build the withdrawWell actions for a chain, recording the
    /// first withdrawal whose destination is the TEMPORAL_GOVERNOR in
    /// _tgWellSpanStart so _markTgWellSpan can protect every later action
    /// that may spend the replenished TG balance (see _tgWellSpanStart).
    /// @param tokenName the registry key of the withdrawn token: xWELL_PROXY
    /// on external chains, GOVTOKEN on Moonbeam
    function _buildWithdrawWellActions(
        Addresses addresses,
        uint256 _chainId,
        WithdrawWell[] memory withdrawWells,
        string memory tokenName
    ) internal {
        ActionType t = _actionTypeForChain(_chainId);

        for (uint256 i = 0; i < withdrawWells.length; i++) {
            if (
                _tgWellSpanStart[uint8(t)] == 0 &&
                addresses.isAddressSet("TEMPORAL_GOVERNOR") &&
                addresses.getAddress(withdrawWells[i].to) ==
                addresses.getAddress("TEMPORAL_GOVERNOR")
            ) {
                _tgWellSpanStart[uint8(t)] =
                    actions.proposalActionTypeCount(t) +
                    1;
            }

            // ActionType passed explicitly (instead of the fork-derived
            // 3-arg _pushAction) so this path also runs in fork-less unit
            // tests; in production builds the active fork always matches
            // _chainId, so behaviour is identical
            _pushAction(
                addresses.getAddress("RESERVE_WELL_HOLDING_DEPOSIT"),
                abi.encodeWithSignature(
                    "withdrawERC20Token(address,address,uint256)",
                    addresses.getAddress(tokenName),
                    addresses.getAddress(withdrawWells[i].to),
                    withdrawWells[i].amount
                ),
                string.concat(
                    "Withdraw ",
                    vm.toString(withdrawWells[i].amount / 1e18),
                    " WELL ",
                    " from the WELL Reserve Holding Deposit Contract on ",
                    _chainId.chainIdToName()
                ),
                t
            );
        }
    }

    /// @notice mark the span from the first withdrawWell(to = TG) action to
    /// the end of the chain's bundle as atomic. Must run after every action
    /// of the chain has been pushed. No-op when the chain has no TG-bound
    /// withdrawal. If the span exceeds maxChunkPayloadBytes() the chunker
    /// fails loudly at simulation/print time (see _computeChunkStarts).
    function _markTgWellSpan(uint256 _chainId) internal {
        ActionType t = _actionTypeForChain(_chainId);
        uint256 start = _tgWellSpanStart[uint8(t)];
        if (start == 0) {
            return;
        }

        uint256 end = actions.proposalActionTypeCount(t);
        if (end > start - 1) {
            _markAtomicGroup(t, start - 1, end - (start - 1));
        }
    }

    /// @notice build the multiRewarder (optional addReward) -> approve ->
    /// notifyRewardAmount groups for a chain. notify pulls the approved reward
    /// tokens, so each group is atomic and kept inside a single VAA.
    function _buildMultiRewarderActions(
        Addresses addresses,
        uint256 _chainId,
        MultiRewarder[] memory multiRewarders
    ) private {
        ActionType t = _actionTypeForChain(_chainId);

        for (uint256 i = 0; i < multiRewarders.length; i++) {
            MultiRewarder memory multiRewarder = multiRewarders[i];

            address distributor = addresses.getAddress(
                multiRewarder.distributor
            );
            address rewardToken = addresses.getAddress(
                multiRewarder.rewardToken
            );

            address vault = addresses.getAddress(multiRewarder.vault);

            uint256 duration = multiRewarder.duration;

            uint256 grpStart = actions.proposalActionTypeCount(t);

            if (vm.envOr("FORCE_ADD_REWARD", false)) {
                _pushAction(
                    vault,
                    abi.encodeWithSignature(
                        "addReward(address,address,uint256)",
                        rewardToken,
                        distributor,
                        duration
                    ),
                    string.concat(
                        "Add reward for ",
                        vm.getLabel(rewardToken),
                        " on ",
                        multiRewarder.vault,
                        " with duration ",
                        vm.toString(duration),
                        " with distributor ",
                        multiRewarder.distributor
                    )
                );
            } else {
                try IMultiRewards(vault).rewardData(rewardToken) returns (
                    address,
                    uint256,
                    uint256,
                    uint256,
                    uint256,
                    uint256
                ) {
                    // No need to call setRewardsDuration because it's already set as 4 weeks and we don't need to set every month
                } catch {
                    _pushAction(
                        vault,
                        abi.encodeWithSignature(
                            "addReward(address,address,uint256)",
                            rewardToken,
                            distributor,
                            duration
                        ),
                        string.concat(
                            "Add reward for ",
                            vm.getLabel(rewardToken),
                            " on ",
                            multiRewarder.vault,
                            " with duration ",
                            vm.toString(duration),
                            " with distributor ",
                            multiRewarder.distributor
                        )
                    );
                }
            }
            // approve the vault to spend the reward token
            _pushAction(
                rewardToken,
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    vault,
                    multiRewarder.reward
                ),
                string.concat(
                    "Approve ",
                    vm.getLabel(rewardToken),
                    " to ",
                    vm.getLabel(vault)
                )
            );

            // Notify reward amount
            _pushAction(
                vault,
                abi.encodeWithSignature(
                    "notifyRewardAmount(address,uint256)",
                    rewardToken,
                    multiRewarder.reward
                ),
                string.concat(
                    "Notify reward amount of ",
                    vm.toString(multiRewarder.reward),
                    " for token ",
                    multiRewarder.rewardToken,
                    " on ",
                    multiRewarder.vault
                )
            );

            _markAtomicGroup(
                t,
                grpStart,
                actions.proposalActionTypeCount(t) - grpStart
            );
        }
    }

    /// @notice build the merkle campaign approve -> acceptConditions ->
    /// createCampaign triples for a chain. The triple is atomic and kept
    /// inside a single VAA.
    function _buildMerkleCampaignActions(
        Addresses addresses,
        uint256 _chainId,
        MekleCampaign[] memory merkleCampaigns
    ) private {
        ActionType t = _actionTypeForChain(_chainId);

        for (uint256 i = 0; i < merkleCampaigns.length; i++) {
            MekleCampaign memory campaign = merkleCampaigns[i];

            uint256 grpStart = actions.proposalActionTypeCount(t);

            address rewardTokenAddress = addresses.getAddress(
                campaign.rewardToken
            );

            // Approve the merkle campaign creator to spend the reward token
            _pushAction(
                rewardTokenAddress,
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
                    campaign.amount
                ),
                "Approve merkle campaign creator"
            );

            // Accept conditions (required before creating campaigns)
            _pushAction(
                addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
                abi.encodeWithSignature("acceptConditions()"),
                "Accept merkle campaign creator conditions"
            );

            // Create the campaign parameters struct
            IMerkleCampaignCreator.CampaignParameters
                memory campaignParams = IMerkleCampaignCreator
                    .CampaignParameters({
                        campaignId: bytes32(0),
                        creator: address(0),
                        rewardToken: rewardTokenAddress,
                        amount: campaign.amount,
                        campaignType: campaign.campaignType,
                        startTimestamp: campaign.startTimestamp,
                        duration: campaign.duration,
                        campaignData: bytes(campaign.campaignData)
                    });

            // Create the merkle campaign
            _pushAction(
                addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
                abi.encodeWithSignature(
                    "createCampaign((bytes32,address,address,uint256,uint32,uint32,uint32,bytes))",
                    campaignParams.campaignId,
                    campaignParams.creator,
                    campaignParams.rewardToken,
                    campaignParams.amount,
                    campaignParams.campaignType,
                    campaignParams.startTimestamp,
                    campaignParams.duration,
                    campaignParams.campaignData
                ),
                string.concat(
                    "Create merkle campaign for token ",
                    vm.getLabel(rewardTokenAddress),
                    " with amount ",
                    vm.toString(campaign.amount)
                )
            );

            _markAtomicGroup(t, grpStart, 3);
        }
    }

    /// @notice build the xWELL bridge-out actions on Ethereum, routed through
    /// the xWELLBridgeFeePayer with ZERO attached value. The adapter's
    /// on-chain-quoted path requires `msg.value == bridgeCost()` exactly, but
    /// proposal action values are frozen at propose time while the gas-priced
    /// quote keeps moving — a direct governor -> adapter call is therefore
    /// near-guaranteed to revert at execution. The fee payer reads the quote
    /// and pays the executor fee from its own pre-funded ETH balance inside
    /// the execution transaction itself, so the quote can never drift.
    function _buildBridgeOutActions(Addresses addresses) private {
        vm.selectFork(ETHEREUM_FORK_ID);

        if (bridgeOuts.length == 0) {
            return;
        }

        address feePayer = addresses.getAddress("xWELL_BRIDGE_FEE_PAYER");
        address xwell = addresses.getAddress("xWELL_PROXY");

        for (uint256 i = 0; i < bridgeOuts.length; i++) {
            BridgeOut memory bridgeOut = bridgeOuts[i];

            address target = addresses.getAddress(
                bridgeOut.target,
                bridgeOut.network
            );

            uint16 wormholeChainId = bridgeOut.network.toWormholeChainId();

            // the fee payer pulls xWELL from the governor, which requires a
            // prior approval
            _pushAction(
                xwell,
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    feePayer,
                    bridgeOut.amount
                ),
                string.concat(
                    "Approve the xWELL Bridge Fee Payer to spend ",
                    vm.toString(bridgeOut.amount / 1e18),
                    " xWELL"
                ),
                ActionType.Ethereum
            );

            _pushAction(
                feePayer,
                abi.encodeWithSignature(
                    "bridgeToRecipient(address,uint256,uint16)",
                    target,
                    bridgeOut.amount,
                    wormholeChainId
                ),
                string.concat(
                    "Bridge ",
                    vm.toString(bridgeOut.amount / 1e18),
                    " xWELL to ",
                    vm.getLabel(target),
                    " on ",
                    bridgeOut.network.chainIdToName(),
                    " via the fee payer (executor fee quoted on-chain at execution)"
                ),
                ActionType.Ethereum
            );
        }
    }

    function _validateMoonbeamDestination(Addresses addresses) private {
        vm.selectFork(MOONBEAM_FORK_ID);

        JsonSpecMoonbeam memory spec = moonbeamActions;

        IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address to = addresses.getAddress(transferFrom.to);
            assertEq(
                well.balanceOf(to),
                wellBalancesBefore[to] + transferFrom.amount,
                string.concat("balance wrong for ", vm.getLabel(to))
            );
        }

        // validate setRewardSpeed calls
        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];
            address market = addresses.getAddress(setRewardSpeed.market);
            ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(
                addresses.getAddress("UNITROLLER")
            );

            if (setRewardSpeed.newSupplySpeed != -1) {
                assertEq(
                    int256(
                        comptrollerV1.supplyRewardSpeeds(
                            uint8(setRewardSpeed.rewardType),
                            address(market)
                        )
                    ),
                    setRewardSpeed.newSupplySpeed,
                    string.concat(
                        "Supply speed for ",
                        vm.getLabel(market),
                        " is incorrect"
                    )
                );
            }

            if (setRewardSpeed.newBorrowSpeed != -1) {
                assertEq(
                    int256(
                        comptrollerV1.borrowRewardSpeeds(
                            uint8(setRewardSpeed.rewardType),
                            address(market)
                        )
                    ),
                    setRewardSpeed.newBorrowSpeed,
                    string.concat(
                        "Borrow speed for ",
                        vm.getLabel(market),
                        " is incorrect"
                    )
                );
            }
        }

        {
            if (spec.stkWellEmissionsPerSecond > 0) {
                address stkGovToken = addresses.getAddress(
                    "STK_GOVTOKEN_PROXY"
                );
                // assert safety module reward speed
                IStakedWell stkWell = IStakedWell(stkGovToken);

                (uint256 emissionsPerSecond, , ) = stkWell.assets(stkGovToken);
                assertEq(
                    emissionsPerSecond,
                    spec.stkWellEmissionsPerSecond,
                    string.concat(
                        "Emissions per second for the Safety Module on Moonbeam is incorrect"
                    )
                );
            }
        }
    }

    function _validateExternalChainActions(
        Addresses addresses,
        uint256 _chainId
    ) private {
        vm.selectFork(_chainId.toForkId());

        JsonSpecExternalChain memory spec = externalChainActions[_chainId];

        // Validate that each reserveAutomationContract has been properly initialized
        if (spec.initSale.reserveAutomationContracts.length > 0) {
            {
                for (
                    uint256 i = 0;
                    i < spec.initSale.reserveAutomationContracts.length;
                    i++
                ) {
                    address reserveAutomationContract = addresses.getAddress(
                        spec.initSale.reserveAutomationContracts[i]
                    );

                    ReserveAutomation automation = ReserveAutomation(
                        reserveAutomationContract
                    );

                    // Check that periodSaleAmount is set and greater than 0
                    assertGt(
                        automation.periodSaleAmount(),
                        0,
                        "ReserveAutomation: periodSaleAmount not initialized"
                    );

                    // Check that saleStartTime is set to a future timestamp
                    assertGt(
                        automation.saleStartTime(),
                        block.timestamp,
                        "ReserveAutomation: saleStartTime not initialized or in the past"
                    );

                    // Check that saleWindow matches the auction period
                    assertEq(
                        automation.saleWindow(),
                        spec.initSale.auctionPeriod,
                        "ReserveAutomation: saleWindow not initialized correctly"
                    );

                    // Check that miniAuctionPeriod is set correctly
                    assertEq(
                        automation.miniAuctionPeriod(),
                        spec.initSale.miniAuctionPeriod,
                        "ReserveAutomation: miniAuctionPeriod not initialized correctly"
                    );

                    // Verify auction period is divisible by mini auction period
                    assertEq(
                        automation.saleWindow() %
                            automation.miniAuctionPeriod(),
                        0,
                        "ReserveAutomation: auction period not divisible by mini auction period"
                    );

                    // Get the reserve asset token
                    address reserveAssetToken = automation.reserveAsset();
                    IERC20 reserveAsset = IERC20(reserveAssetToken);

                    // Verify the contract has the expected amount of reserves
                    uint256 actualReserves = reserveAsset.balanceOf(
                        reserveAutomationContract
                    );

                    // Check that the balance has increased by the expected amount
                    uint256 balanceIncrease = actualReserves -
                        reserveAutomationBalancesBefore[
                            reserveAutomationContract
                        ];

                    // Verify that the reserves match any transferReserves operation targeting this contract
                    for (uint256 j = 0; j < spec.transferReserves.length; j++) {
                        if (
                            addresses.getAddress(spec.transferReserves[j].to) ==
                            reserveAutomationContract
                        ) {
                            assertApproxEqRel(
                                balanceIncrease,
                                spec.transferReserves[j].amount,
                                0.01e18,
                                "ReserveAutomation: reserves do not match transferReserves amount"
                            );
                        }
                    }
                }
            }
        }

        // Check balances for transferFroms
        {
            for (uint256 i = 0; i < spec.transferFroms.length; i++) {
                address to = addresses.getAddress(spec.transferFroms[i].to);
                address token = addresses.getAddress(
                    spec.transferFroms[i].token
                );

                if (token == addresses.getAddress("xWELL_PROXY")) {
                    if (
                        _chainId == ETHEREUM_CHAIN_ID &&
                        to ==
                        addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
                    ) {
                        // the xWELL transferred to the governor is burned by
                        // the bridge-out actions in the same proposal, so
                        // its balance must be unchanged after execution
                        assertApproxEqAbs(
                            IERC20(token).balanceOf(to),
                            wellBalancesBefore[to],
                            10e18, // tolerates 10 well as margin error
                            string.concat(
                                "balance changed for ",
                                vm.getLabel(to)
                            )
                        );
                    } else if (
                        to == addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
                    ) {
                        // For ECOSYSTEM_RESERVE_PROXY, we need to account for both transferFroms and withdrawWell
                        uint256 totalAmount = spec.transferFroms[i].amount;

                        // Add any withdrawWell amounts to the same recipient
                        for (uint256 j = 0; j < spec.withdrawWell.length; j++) {
                            if (
                                addresses.getAddress(spec.withdrawWell[j].to) ==
                                to
                            ) {
                                totalAmount += spec.withdrawWell[j].amount;
                            }
                        }

                        assertEq(
                            IERC20(token).balanceOf(to),
                            wellBalancesBefore[to] + totalAmount,
                            string.concat("balance wrong for ", vm.getLabel(to))
                        );
                    } else {
                        assertEq(
                            IERC20(token).balanceOf(to),
                            wellBalancesBefore[to] +
                                spec.transferFroms[i].amount,
                            string.concat(
                                "balance changed for ",
                                vm.getLabel(to)
                            )
                        );
                    }
                }
            }
        }

        // Check balances for withdrawWell operations that don't have a corresponding transferFrom
        {
            for (uint256 i = 0; i < spec.withdrawWell.length; i++) {
                address to = addresses.getAddress(spec.withdrawWell[i].to);

                // Skip if this recipient was already checked in the transferFroms loop
                bool alreadyChecked = false;
                for (uint256 j = 0; j < spec.transferFroms.length; j++) {
                    if (
                        addresses.getAddress(spec.transferFroms[j].to) == to &&
                        addresses.getAddress(spec.transferFroms[j].token) ==
                        addresses.getAddress("xWELL_PROXY")
                    ) {
                        alreadyChecked = true;
                        break;
                    }
                }

                // skip the proposal executor itself (TemporalGovernor on
                // external chains, MultichainGovernorV2 on Ethereum) since
                // its balance is also changed by the other proposal actions
                bool isProposalExecutor = _chainId == ETHEREUM_CHAIN_ID
                    ? to == addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
                    : to == addresses.getAddress("TEMPORAL_GOVERNOR");

                if (!alreadyChecked && !isProposalExecutor) {
                    assertEq(
                        IERC20(addresses.getAddress("xWELL_PROXY")).balanceOf(
                            to
                        ),
                        wellBalancesBefore[to] + spec.withdrawWell[i].amount,
                        string.concat(
                            "withdrawWell: balance wrong for ",
                            vm.getLabel(to)
                        )
                    );
                }
            }
        }

        {
            // validate emissions per second for the Safety Module — only
            // when this MIP actually sets it. Matches the build-side gate
            // `if (spec.stkWellEmissionsPerSecond > 0)` above. Lets split
            // MIPs (e.g. x51b) ship an empty Optimism stub without asserting
            // on-chain emissions equal zero.
            if (spec.stkWellEmissionsPerSecond > 0) {
                IStakedWell stkWell = IStakedWell(
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
                );

                (uint256 emissionsPerSecond, , ) = stkWell.assets(
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
                );
                assertEq(
                    emissionsPerSecond,
                    spec.stkWellEmissionsPerSecond,
                    "Emissions per second for the Safety Module is incorrect"
                );
            }
        }

        {
            IMultiRewardDistributor distributor = IMultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            // validate setRewardSpeed calls
            for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
                SetMRDRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[
                    i
                ];

                IMultiRewardDistributor.MarketConfig[]
                    memory _emissionConfigs = distributor.getAllMarketConfigs(
                        MToken(addresses.getAddress(setRewardSpeed.market))
                    );

                for (uint256 j = 0; j < _emissionConfigs.length; j++) {
                    IMultiRewardDistributor.MarketConfig
                        memory _config = _emissionConfigs[j];
                    if (
                        _config.emissionToken ==
                        addresses.getAddress(setRewardSpeed.emissionToken)
                    ) {
                        address market = addresses.getAddress(
                            setRewardSpeed.market
                        );

                        if (setRewardSpeed.newSupplySpeed != -1) {
                            assertEq(
                                int256(_config.supplyEmissionsPerSec),
                                setRewardSpeed.newSupplySpeed,
                                string.concat(
                                    "Supply speed for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            );
                        }

                        if (setRewardSpeed.newBorrowSpeed != -1) {
                            assertEq(
                                int256(_config.borrowEmissionsPerSec),
                                setRewardSpeed.newBorrowSpeed,
                                string.concat(
                                    "Borrow speed for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            );
                        }

                        if (setRewardSpeed.newEndTime != -1) {
                            assertEq(
                                int256(_config.endTime),
                                setRewardSpeed.newEndTime,
                                string.concat(
                                    "End time for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            );
                        }
                    }
                }
            }
        }

        // Validate MultiRewarder configurations
        for (uint256 i = 0; i < spec.multiRewarder.length; i++) {
            MultiRewarder memory rewarder = spec.multiRewarder[i];
            address vault = addresses.getAddress(rewarder.vault);
            IMultiRewards multiRewards = IMultiRewards(vault);

            // Get reward data from the contract
            (
                address rewardsDistributor,
                uint256 rewardsDuration,
                uint256 periodFinish,
                uint256 rewardRate, // rewardPerTokenStored
                ,

            ) = multiRewards.rewardData(
                    addresses.getAddress(rewarder.rewardToken)
                ); // lastUpdateTime

            // Validate reward configuration
            assertEq(
                rewardsDistributor,
                addresses.getAddress(rewarder.distributor),
                string.concat(
                    "Incorrect rewards distributor for token ",
                    rewarder.rewardToken,
                    " in vault ",
                    vm.getLabel(vault)
                )
            );

            assertEq(
                rewardsDuration,
                rewarder.duration,
                string.concat(
                    "Incorrect rewards duration for token ",
                    rewarder.rewardToken,
                    " in vault ",
                    vm.getLabel(vault)
                )
            );

            // Calculate expected reward rate and validate
            // Match MultiRewards.sol logic (lines 619-627):
            // remaining = periodFinish - block.timestamp
            // leftover = remaining * rewardRate
            // newRewardRate = (reward + leftover) / duration
            uint256 leftover = 0;
            if (
                leftoverRewardRate > 0 && block.timestamp < leftoverPeriodFinish
            ) {
                uint256 remaining = leftoverPeriodFinish - block.timestamp;
                leftover = remaining * leftoverRewardRate;
            }
            uint256 expectedRewardRate = (rewarder.reward + leftover) /
                rewardsDuration;

            // Validate reward rate
            assertApproxEqRel(
                rewardRate,
                expectedRewardRate,
                0.01e18, // 1% tolerance for small rounding differences
                string.concat(
                    "Incorrect reward rate for token ",
                    rewarder.rewardToken,
                    " in vault ",
                    vm.getLabel(vault)
                )
            );

            // Validate period finish
            assertGt(
                periodFinish,
                startTimeStamp,
                string.concat(
                    "Reward period should not be finished for token ",
                    rewarder.rewardToken
                )
            );
        }

        // Validate Merkle campaign configurations
        for (uint256 i = 0; i < spec.merkleCampaigns.length; i++) {
            MekleCampaign memory campaign = spec.merkleCampaigns[i];

            // campaigns are created by the proposal executor on this chain:
            // the TemporalGovernor externally, the governor on Ethereum
            address campaignCreator = _chainId == ETHEREUM_CHAIN_ID
                ? addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY")
                : addresses.getAddress("TEMPORAL_GOVERNOR");

            IMerkleCampaignCreator.CampaignParameters
                memory campaignParameters = IMerkleCampaignCreator
                    .CampaignParameters({
                        campaignId: bytes32(0),
                        creator: campaignCreator,
                        rewardToken: addresses.getAddress(campaign.rewardToken),
                        amount: campaign.amount,
                        campaignType: campaign.campaignType,
                        startTimestamp: campaign.startTimestamp,
                        duration: campaign.duration,
                        campaignData: bytes(campaign.campaignData)
                    });

            // Check if the campaign is created
            bytes32 campaignId = IMerkleCampaignCreator(
                addresses.getAddress("MERKLE_CAMPAIGN_CREATOR")
            ).campaignId(campaignParameters);

            assertNotEq(
                campaignId,
                bytes32(0),
                string.concat(
                    "Merkle campaign should be created for token ",
                    campaign.rewardToken
                )
            );

            // Validate that the campaign data is correct
            IMerkleCampaignCreator.CampaignParameters
                memory returnedCampaignParams = IMerkleCampaignCreator(
                    addresses.getAddress("MERKLE_CAMPAIGN_CREATOR")
                ).campaign(campaignId);

            assertEq(
                returnedCampaignParams.creator,
                campaignParameters.creator,
                "Creator should be correct"
            );

            assertEq(
                returnedCampaignParams.rewardToken,
                campaignParameters.rewardToken,
                "Reward token should be correct"
            );

            assertApproxEqRel(
                returnedCampaignParams.amount,
                campaignParameters.amount -
                    ((campaignParameters.amount * 1) / 100),
                1e16,
                "Amount should be correct"
            ); // reduce the 1% fee

            assertEq(
                returnedCampaignParams.campaignType,
                campaignParameters.campaignType,
                "Campaign type should be correct"
            );

            assertEq(
                returnedCampaignParams.startTimestamp,
                campaignParameters.startTimestamp,
                "Start timestamp should be correct"
            );

            assertEq(
                returnedCampaignParams.duration,
                campaignParameters.duration,
                "Duration should be correct"
            );

            assertEq(
                returnedCampaignParams.campaignData,
                bytes(campaign.campaignData),
                "Campaign data should be correct"
            );
        }
    }

    function _validateTransferDestination(
        string memory destination
    ) internal pure {
        require(
            keccak256(abi.encodePacked(destination)) != keccak256("MRD_IMPL"),
            "should not transfer funds to MRD logic contract"
        );

        require(
            keccak256(abi.encodePacked(destination)) !=
                keccak256("ECOSYSTEM_RESERVE_IMPL"),
            "should not transfer funds to Ecosystem Reserve logic contract"
        );
        require(
            keccak256(abi.encodePacked(destination)) !=
                keccak256("STK_GOVTOKEN_IMPL"),
            "should not transfer funds to Safety Module logic contract"
        );
    }

    function _parseTimestamps(string memory encodedJson) private {
        // parse start timestamp
        string memory filter = ".startTimeStamp";
        bytes memory parsedJson = vm.parseJson(encodedJson, filter);
        startTimeStamp = abi.decode(parsedJson, (uint256));

        // parse end timestamp
        filter = ".endTimeSTamp";
        parsedJson = vm.parseJson(encodedJson, filter);
        endTimeStamp = abi.decode(parsedJson, (uint256));

        // validate timestamps
        assertGt(
            endTimeStamp,
            startTimeStamp,
            "endTimeStamp must be greater than startTimeStamp"
        );

        assertGe(
            endTimeStamp - startTimeStamp,
            3 weeks,
            "endTimeStamp - startTimeStamp must be greater than 3 weeks"
        );
    }
}

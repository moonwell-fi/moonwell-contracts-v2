//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID, BASE_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ReserveAutomation} from "@protocol/market/ReserveAutomation.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IStellaSwapRewarder} from "@protocol/interfaces/IStellaSwapRewarder.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
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

contract RewardsDistributionTemplate is HybridProposal, Networks {
    using SafeCast for *;
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;
    using ProposalActions for *;
    using stdStorage for StdStorage;

    struct BridgeWell {
        uint256 amount;
        uint256 nativeValue;
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

    struct AddRewardInfo {
        uint256 amount;
        uint256 endTimestamp;
        uint256 pid;
        uint256 rewardPerSec;
        string target;
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

    struct JsonSpecMoonbeam {
        AddRewardInfo addRewardInfo;
        BridgeWell[] bridgeWells;
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
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

    bytes public constant payloadMerkleCampaignBase =
        hex"000000000000000000000000a88594d404727625a9437c3f886c7643872296ae00000000000000000000000000000000000000000000000000000000000000e000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000000000000000000000000000000000000120000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000001600000000000000000000000000000000000000000000000000000000000000180000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function name() external pure override returns (string memory) {
        return "MIP Rewards Distribution";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function initProposal(Addresses addresses) public override {
        etch(vm, addresses);

        string memory encodedJson = vm.readFile(
            vm.envString("MIP_REWARDS_PATH")
        );

        _parseTimestamps(encodedJson);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _saveExternalChainActions(addresses, encodedJson, chainId);

                // save well balances before
                IERC20 xwell = IERC20(addresses.getAddress("xWELL_PROXY"));
                address mrd = addresses.getAddress("MRD_PROXY");
                wellBalancesBefore[mrd] = xwell.balanceOf(mrd);

                address dexRelayer = addresses.getAddress("DEX_RELAYER");
                wellBalancesBefore[dexRelayer] = xwell.balanceOf(dexRelayer);

                address reserve = addresses.getAddress(
                    "ECOSYSTEM_RESERVE_PROXY"
                );
                wellBalancesBefore[reserve] = xwell.balanceOf(reserve);

                // Save initial balances for reserve automation contracts
                JsonSpecExternalChain memory spec = externalChainActions[
                    chainId
                ];
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
                    ] = IERC20(reserveAsset).balanceOf(
                        reserveAutomationContract
                    );
                }
            }
        }

        vm.selectFork(MOONBEAM_FORK_ID);

        {
            // save well balances before so we can check if the transferFrom was successful
            IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));

            address governor = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_PROXY"
            );
            wellBalancesBefore[governor] = well.balanceOf(governor);

            address unitroller = addresses.getAddress("UNITROLLER");
            wellBalancesBefore[unitroller] = well.balanceOf(unitroller);

            address reserve = addresses.getAddress("ECOSYSTEM_RESERVE_PROXY");
            wellBalancesBefore[reserve] = well.balanceOf(reserve);

            address stellaSwapRewarder = addresses.getAddress(
                "STELLASWAP_REWARDER"
            );
            wellBalancesBefore[stellaSwapRewarder] = well.balanceOf(
                stellaSwapRewarder
            );
        }
        _saveMoonbeamActions(addresses, encodedJson);
    }

    function build(Addresses addresses) public override {
        _buildMoonbeamActions(addresses);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _buildExternalChainActions(addresses, chainId);
            }
        }
    }

    function beforeSimulationHook(Addresses addresses) public override {
        _validateSafetyModuleActions();

        vm.selectFork(MOONBEAM_FORK_ID);

        // Mock approval for F-GLMR-DEVGRANT to allow the transfer to succeed
        vm.startPrank(addresses.getAddress("F-GLMR-DEVGRANT"));
        IERC20(addresses.getAddress("GOVTOKEN")).approve(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            11669037203603280000000000 // 1.166903720360328e25
        );
        vm.stopPrank();

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
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        // encode gasLimit and relayer address since is stored in a single slot
        // relayer is first due to how evm pack values into a single storage
        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);

                vm.store(
                    address(wormholeBridgeAdapter),
                    bytes32(uint256(153)),
                    encodedData
                );

                if (chainId == BASE_CHAIN_ID) {
                    // mock the MTOKEN_VIRTUAL balance
                    deal(
                        addresses.getAddress("VIRTUAL"),
                        addresses.getAddress("MOONWELL_VIRTUAL"),
                        14916685444629005000000
                    );
                }

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

        vm.selectFork(BASE_FORK_ID);

        vm.selectFork(MOONBEAM_FORK_ID);
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

    function validate(Addresses addresses, address) public override {
        _validateMoonbeam(addresses);

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _validateExternalChainActions(addresses, chainId);
            }
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

            // Base actions should not configure Safety Module assets
            if (actions[i].actionType == ActionType.Base) {
                require(
                    selector != configureAssetsSelector,
                    string.concat(
                        "Base action ",
                        vm.toString(i),
                        " uses configureAssets. Safety Module on Base should not be configured."
                    )
                );
            }
        }
    }

    function _saveMoonbeamActions(
        Addresses addresses,
        string memory data
    ) private {
        string memory chain = ".1284";

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecMoonbeam memory spec = abi.decode(
            parsedJson,
            (JsonSpecMoonbeam)
        );

        moonbeamActions.addRewardInfo = spec.addRewardInfo;

        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            moonbeamActions.bridgeWells.push(spec.bridgeWells[i]);
        }

        assertGe(
            spec.stkWellEmissionsPerSecond,
            0,
            "stkWellEmissionsPerSecond must be greater than 0"
        );

        assertLe(
            spec.stkWellEmissionsPerSecond,
            5e18,
            "stkWellEmissionsPerSecond must be less than 1e18"
        );

        moonbeamActions.stkWellEmissionsPerSecond = spec
            .stkWellEmissionsPerSecond;

        uint256 totalEpochRewards = 0;

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            // check for duplications
            for (
                uint256 j = 0;
                j < moonbeamActions.setRewardSpeed.length;
                j++
            ) {
                SetRewardSpeed memory existingSetRewardSpeed = moonbeamActions
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
                    spec.setRewardSpeed[i].newSupplySpeed
                ) * (endTimeStamp - startTimeStamp);

                uint256 borrowAmount = uint256(
                    spec.setRewardSpeed[i].newBorrowSpeed
                ) * (endTimeStamp - startTimeStamp);

                totalEpochRewards += supplyAmount + borrowAmount;
            }

            moonbeamActions.setRewardSpeed.push(setRewardSpeed);
        }

        // save transfer froms
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            // check for duplications
            for (uint256 j = 0; j < moonbeamActions.transferFroms.length; j++) {
                TransferFrom memory existingTransferFrom = moonbeamActions
                    .transferFroms[j];

                require(
                    keccak256(abi.encodePacked(existingTransferFrom.to)) !=
                        keccak256("COMPTROLLER"),
                    "should not transfer funds to COMPTROLLER logic contract"
                );
            }

            if (
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("UNITROLLER")
            ) {
                assertApproxEqRel(
                    spec.transferFroms[i].amount,
                    totalEpochRewards,
                    0.01e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            if (
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
            ) {
                assertApproxEqRel(
                    spec.transferFroms[i].amount,
                    spec.stkWellEmissionsPerSecond *
                        (endTimeStamp - startTimeStamp),
                    0.1e18,
                    "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
                );
            }

            moonbeamActions.transferFroms.push(spec.transferFroms[i]);
        }
    }

    function _saveStkWellEmissionsPerSecond(
        string memory data,
        string memory prefix,
        uint256 _chainId
    ) private {
        require(
            _chainId != BASE_CHAIN_ID,
            "Safety Module on Base should not be configured"
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
            if (
                addresses.getAddress(transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY") &&
                addresses.getAddress(transferFroms[i].from) ==
                addresses.getAddress("TEMPORAL_GOVERNOR") &&
                addresses.getAddress(transferFroms[i].token) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                console.log("totalWellEpochRewards", totalWellEpochRewards);
                console.log("transferFroms[i].amount", transferFroms[i].amount);
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
                console.log("totalOpEpochRewards", totalOpEpochRewards);
                console.log("transferFroms[i].amount", transferFroms[i].amount);
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

        if (_chainId != BASE_CHAIN_ID) {
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

        if (_chainId != BASE_CHAIN_ID) {
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

    function _buildMoonbeamActions(Addresses addresses) private {
        vm.selectFork(MOONBEAM_FORK_ID);

        JsonSpecMoonbeam memory spec = moonbeamActions;
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address token = addresses.getAddress(transferFrom.token);
            address from = addresses.getAddress(transferFrom.from);
            address to = addresses.getAddress(transferFrom.to);

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
        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            BridgeWell memory bridgeWell = spec.bridgeWells[i];

            address target = addresses.getAddress(
                bridgeWell.target,
                bridgeWell.network
            );

            address router = addresses.getAddress("xWELL_ROUTER");
            address well = addresses.getAddress("GOVTOKEN");

            // first approve
            _pushAction(
                well,
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    router,
                    bridgeWell.amount
                ),
                string.concat(
                    "Approve xWELL Router to spend ",
                    vm.toString(bridgeWell.amount / 1e18),
                    " ",
                    vm.getLabel(well)
                ),
                ActionType.Moonbeam
            );

            uint256 wormholeChainId = bridgeWell.network.toWormholeChainId();

            _pushAction(
                router,
                bridgeWell.nativeValue,
                abi.encodeWithSignature(
                    "bridgeToRecipient(address,uint256,uint16)",
                    target,
                    bridgeWell.amount,
                    wormholeChainId
                ),
                string.concat(
                    "Bridge ",
                    vm.toString(bridgeWell.amount / 1e18),
                    " WELL to ",
                    vm.getLabel(target),
                    " on ",
                    bridgeWell.network.chainIdToName()
                ),
                ActionType.Moonbeam
            );
        }

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

        AddRewardInfo memory stellaSwapReward = spec.addRewardInfo;
        uint256 calculatedAmount = stellaSwapReward.amount;
        // first approve
        _pushAction(
            addresses.getAddress("GOVTOKEN"),
            abi.encodeWithSignature(
                "approve(address,uint256)",
                addresses.getAddress(stellaSwapReward.target),
                calculatedAmount
            ),
            string.concat(
                "Approve StellaSwap spend ",
                vm.toString(calculatedAmount / 1e18),
                " WELL"
            ),
            ActionType.Moonbeam
        );
        _pushAction(
            addresses.getAddress(stellaSwapReward.target),
            abi.encodeWithSignature(
                "addRewardInfo(uint256,uint256,uint256)",
                stellaSwapReward.pid,
                stellaSwapReward.endTimestamp,
                stellaSwapReward.rewardPerSec
            ),
            string.concat(
                "Add reward info for pool ",
                vm.toString(stellaSwapReward.pid),
                " on StellaSwap.\nReward per second: ",
                vm.toString(uint256(stellaSwapReward.rewardPerSec)),
                "\nEnd timestamp: ",
                vm.toString(stellaSwapReward.endTimestamp)
            ),
            ActionType.Moonbeam
        );

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
    }

    function _buildExternalChainActions(
        Addresses addresses,
        uint256 _chainId
    ) private {
        vm.selectFork(_chainId.toForkId());

        JsonSpecExternalChain memory spec = externalChainActions[_chainId];

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address token = addresses.getAddress(transferFrom.token);
            address from = addresses.getAddress(transferFrom.from);
            address to = addresses.getAddress(transferFrom.to);

            if (from != addresses.getAddress("TEMPORAL_GOVERNOR")) {
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

        // withdraw reserves from the Market Reserve ERC20 Holding Deposit contract
        for (uint256 i = 0; i < spec.withdrawWell.length; i++) {
            _pushAction(
                addresses.getAddress("RESERVE_WELL_HOLDING_DEPOSIT"),
                abi.encodeWithSignature(
                    "withdrawERC20Token(address,address,uint256)",
                    addresses.getAddress("xWELL_PROXY"),
                    addresses.getAddress(spec.withdrawWell[i].to),
                    spec.withdrawWell[i].amount
                ),
                string.concat(
                    "Withdraw ",
                    vm.toString(spec.withdrawWell[i].amount / 1e18),
                    " WELL ",
                    " from the WELL Reserve Holding Deposit Contract on ",
                    _chainId.chainIdToName()
                )
            );
        }

        for (uint256 i = 0; i < spec.transferReserves.length; i++) {
            IERC20 underlying = IERC20(
                MErc20(addresses.getAddress(spec.transferReserves[i].market))
                    .underlying()
            );

            _pushAction(
                addresses.getAddress(spec.transferReserves[i].market),
                abi.encodeWithSignature(
                    "_reduceReserves(uint256)",
                    spec.transferReserves[i].amount
                ),
                string.concat(
                    "Withdraw ",
                    vm.toString(
                        spec.transferReserves[i].amount / underlying.decimals()
                    ),
                    " ",
                    underlying.symbol(),
                    " from ",
                    spec.transferReserves[i].market,
                    " on ",
                    _chainId.chainIdToName()
                )
            );

            _pushAction(
                address(underlying),
                abi.encodeWithSignature(
                    "transfer(address,uint256)",
                    addresses.getAddress(spec.transferReserves[i].to),
                    spec.transferReserves[i].amount
                ),
                string.concat(
                    "Transfer ",
                    vm.toString(
                        spec.transferReserves[i].amount / underlying.decimals()
                    ),
                    " ",
                    underlying.symbol(),
                    " to ",
                    spec.transferReserves[i].to,
                    " on ",
                    _chainId.chainIdToName()
                )
            );
        }

        // Process initSale if it exists in the JSON and has valid data
        if (
            spec.initSale.auctionPeriod != 0 ||
            spec.initSale.reserveAutomationContracts.length > 0
        ) {
            InitSale memory initSale = spec.initSale;

            for (
                uint256 i = 0;
                i < initSale.reserveAutomationContracts.length;
                i++
            ) {
                address reserveAutomationContract = addresses.getAddress(
                    initSale.reserveAutomationContracts[i]
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
                        vm.getLabel(
                            addresses.getAddress(
                                initSale.reserveAutomationContracts[i]
                            )
                        ),
                        " on ",
                        _chainId.chainIdToName()
                    )
                );
            }
        }

        for (uint256 i = 0; i < spec.multiRewarder.length; i++) {
            MultiRewarder memory multiRewarder = spec.multiRewarder[i];

            address distributor = addresses.getAddress(
                multiRewarder.distributor
            );
            address rewardToken = addresses.getAddress(
                multiRewarder.rewardToken
            );

            address vault = addresses.getAddress(multiRewarder.vault);

            uint256 duration = multiRewarder.duration;

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
        }

        // Process Merkle campaigns
        for (uint256 i = 0; i < spec.merkleCampaigns.length; i++) {
            MekleCampaign memory campaign = spec.merkleCampaigns[i];

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
        }
    }

    function _validateMoonbeam(Addresses addresses) private {
        vm.selectFork(MOONBEAM_FORK_ID);

        JsonSpecMoonbeam memory spec = moonbeamActions;

        IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address to = addresses.getAddress(transferFrom.to);
            if (to == addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")) {
                //  amount must be transferred as part of the DEX rewards and
                //  bridge calls
                assertApproxEqAbs(
                    well.balanceOf(to),
                    wellBalancesBefore[to],
                    10e18, // tolerates 10 well as margin error
                    string.concat("balance changed for ", vm.getLabel(to))
                );
            } else {
                assertEq(
                    well.balanceOf(to),
                    wellBalancesBefore[to] + transferFrom.amount,
                    string.concat("balance wrong for ", vm.getLabel(to))
                );
            }
        }

        // assert xwell router allowance
        assertEq(
            well.allowance(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                addresses.getAddress("xWELL_ROUTER")
            ),
            0,
            "xWELL Router should not have an open allowance after execution"
        );

        {
            // assert bridgeToRecipient value is correct
            xWELLRouter router = xWELLRouter(
                addresses.getAddress("xWELL_ROUTER")
            );

            WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );

            uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

            IWormholeRelayer relayer = IWormholeRelayer(
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY")
            );

            for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
                BridgeWell memory bridgeWell = spec.bridgeWells[i];

                uint16 wormholeChainId = bridgeWell.network.toWormholeChainId();

                (uint256 quoteEVMDeliveryPrice, ) = relayer
                    .quoteEVMDeliveryPrice(wormholeChainId, 0, gasLimit);

                uint256 expectedValue = quoteEVMDeliveryPrice * 5;

                assertEq(
                    router.bridgeCost(wormholeChainId),
                    quoteEVMDeliveryPrice,
                    "Bridge cost is incorrect"
                );

                // bridgeWell value must be close to the expected value
                assertApproxEqRel(
                    bridgeWell.nativeValue,
                    expectedValue,
                    0.20e18, // 20% tolarance due to gas cost changes
                    "Bridge value is incorrect"
                );
            }
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

        // validate dex rewards
        AddRewardInfo memory addRewardInfo = spec.addRewardInfo;
        address stellaSwapRewarder = addresses.getAddress(
            "STELLASWAP_REWARDER"
        );
        IStellaSwapRewarder stellaSwap = IStellaSwapRewarder(
            stellaSwapRewarder
        );
        // check allowance tolerating a dust wei amount
        assertApproxEqAbs(
            well.allowance(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                stellaSwapRewarder
            ),
            0,
            1e18,
            string.concat(
                "StellaSwap Rewarder should not have an open allowance after execution"
            )
        );

        assertApproxEqAbs(
            well.balanceOf(stellaSwapRewarder),
            wellBalancesBefore[stellaSwapRewarder] + addRewardInfo.amount,
            10e18,
            string.concat(
                "StellaSwap Rewarder should have received the correct amount of WELL"
            )
        );

        uint256 blockTimestamp = block.timestamp;

        // block.timestamp must be in the current reward period to the getter
        // functions return the correct values
        vm.warp(addRewardInfo.endTimestamp - 1);
        assertEq(
            stellaSwap.poolRewardsPerSec(addRewardInfo.pid),
            addRewardInfo.rewardPerSec,
            string.concat("Reward per second for StellaSwap is incorrect")
        );
        assertEq(
            stellaSwap.currentEndTimestamp(addRewardInfo.pid),
            addRewardInfo.endTimestamp,
            string.concat("End timestamp for StellaSwap is incorrect")
        );

        // warp back to current block.timestamp
        vm.warp(blockTimestamp);
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
                    if (to == addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")) {
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

                bool isTempGov = to ==
                    addresses.getAddress("TEMPORAL_GOVERNOR");

                if (!alreadyChecked && !isTempGov) {
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
            // validate emissions per second for the Safety Module
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

            IMerkleCampaignCreator.CampaignParameters
                memory campaignParameters = IMerkleCampaignCreator
                    .CampaignParameters({
                        campaignId: bytes32(0),
                        creator: addresses.getAddress("TEMPORAL_GOVERNOR"),
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

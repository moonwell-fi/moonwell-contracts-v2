//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {IStellaSwapRewarder} from "@protocol/interfaces/IStellaSwapRewarder.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultiRewardDistributor} from "@protocol/rewards/MultiRewardDistributor.sol";
import {MultiRewardDistributorCommon} from "@protocol/rewards/MultiRewardDistributorCommon.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

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

    struct JsonSpecMoonbeam {
        AddRewardInfo addRewardInfo;
        BridgeWell[] bridgeWells;
        SetRewardSpeed[] setRewardSpeed;
        int256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    struct JsonSpecExternalChain {
        SetMRDRewardSpeed[] setRewardSpeed;
        int256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    JsonSpecMoonbeam moonbeamActions;

    uint256 chainId;
    uint256 startTimeStamp;
    uint256 endTimeStamp;

    mapping(uint256 chainid => JsonSpecExternalChain) externalChainActions;

    /// @notice we save this value to check if the transferFrom amount was successfully transferred
    mapping(address => uint256) public wellBalancesBefore;

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

        string memory filter = ".startTimeStamp";

        bytes memory parsedJson = vm.parseJson(encodedJson, filter);

        startTimeStamp = abi.decode(parsedJson, (uint256));

        filter = ".endTimeSTamp";

        parsedJson = vm.parseJson(encodedJson, filter);

        endTimeStamp = abi.decode(parsedJson, (uint256));

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

        for (uint256 i = 0; i < networks.length; i++) {
            chainId = networks[i].chainId;
            if (chainId != MOONBEAM_CHAIN_ID) {
                vm.selectFork(networks[i].forkId);
                _saveExternalChainActions(addresses, encodedJson, chainId);

                // save well balances before so we can check if the transferFrom was successful
                IERC20 xwell = IERC20(addresses.getAddress("xWELL_PROXY"));
                address mrd = addresses.getAddress("MRD_PROXY");
                wellBalancesBefore[mrd] = xwell.balanceOf(mrd);

                address dexRelayer = addresses.getAddress("DEX_RELAYER");
                wellBalancesBefore[dexRelayer] = xwell.balanceOf(dexRelayer);

                address reserve = addresses.getAddress(
                    "ECOSYSTEM_RESERVE_PROXY"
                );
                wellBalancesBefore[reserve] = xwell.balanceOf(reserve);
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

    function beforeSimulationHook(Addresses addresses) public override {
        // mock relayer so we can simulate bridging well
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter();
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        // we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
        // call it must switch forks
        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        // set mock as the wormholeRelayer address on bridge adapter
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

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
            }
        }

        vm.selectFork(primaryForkId());

        // stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );
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
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(primaryForkId());

        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );
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

        if (spec.stkWellEmissionsPerSecond != -1) {
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
        }

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
                    int256(spec.transferFroms[i].amount),
                    spec.stkWellEmissionsPerSecond *
                        int256(endTimeStamp - startTimeStamp),
                    0.1e18,
                    "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
                );
            }

            moonbeamActions.transferFroms.push(spec.transferFroms[i]);
        }
    }

    function _saveExternalChainActions(
        Addresses addresses,
        string memory data,
        uint256 _chainId
    ) private {
        string memory chain = string.concat(".", vm.toString(_chainId));

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecExternalChain memory spec = abi.decode(
            parsedJson,
            (JsonSpecExternalChain)
        );

        if (spec.stkWellEmissionsPerSecond != -1) {
            assertLe(
                spec.stkWellEmissionsPerSecond,
                5e18,
                "stkWellEmissionsPerSecond must be less than 5e18"
            );

            externalChainActions[_chainId].stkWellEmissionsPerSecond = spec
                .stkWellEmissionsPerSecond;
        }

        uint256 totalWellEpochRewards = 0;
        uint256 totalOpEpochRewards = 0;

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
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
                        addresses.getAddress(spec.setRewardSpeed[i].market) ||
                        addresses.getAddress(
                            existingSetRewardSpeed.emissionToken
                        ) !=
                        addresses.getAddress(
                            spec.setRewardSpeed[i].emissionToken
                        ),
                    "Duplication in setRewardSpeeds"
                );
            }

            if (spec.setRewardSpeed[i].newBorrowSpeed != -1) {
                assertGe(
                    spec.setRewardSpeed[i].newBorrowSpeed,
                    1,
                    "Borrow speed must be greater or equal to 1"
                );
            }

            int256 supplySpeed = spec.setRewardSpeed[i].newSupplySpeed;
            int256 borrowSpeed = spec.setRewardSpeed[i].newBorrowSpeed;
            if (
                addresses.getAddress(spec.setRewardSpeed[i].emissionToken) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                assertLe(
                    supplySpeed,
                    10e18,
                    "Supply speed must be less than 10 WELL per second"
                );

                uint256 supplyAmount = supplySpeed != int256(-1)
                    ? uint256(supplySpeed) *
                        (uint256(spec.setRewardSpeed[i].newEndTime) -
                            startTimeStamp)
                    : 0;

                uint256 borrowAmount = borrowSpeed != int256(-1)
                    ? (uint256(borrowSpeed) *
                        (uint256(spec.setRewardSpeed[i].newEndTime) -
                            startTimeStamp))
                    : 0;

                totalWellEpochRewards += supplyAmount + borrowAmount;
            }

            // TODO add USDC assertion in the future
            if (
                chainId == OPTIMISM_CHAIN_ID &&
                addresses.getAddress(spec.setRewardSpeed[i].emissionToken) ==
                addresses.getAddress("OP", OPTIMISM_CHAIN_ID)
            ) {
                uint256 supplyAmount = supplySpeed != int256(-1)
                    ? uint256(supplySpeed) *
                        (uint256(spec.setRewardSpeed[i].newEndTime) -
                            startTimeStamp)
                    : 0;

                uint256 borrowAmount = borrowSpeed != int256(-1)
                    ? (uint256(borrowSpeed) *
                        (uint256(spec.setRewardSpeed[i].newEndTime) -
                            startTimeStamp))
                    : 0;

                totalOpEpochRewards += supplyAmount + borrowAmount;
            }

            externalChainActions[_chainId].setRewardSpeed.push(
                spec.setRewardSpeed[i]
            );
        }

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            if (
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY") &&
                addresses.getAddress(spec.transferFroms[i].from) ==
                addresses.getAddress("TEMPORAL_GOVERNOR") &&
                addresses.getAddress(spec.transferFroms[i].token) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                assertApproxEqRel(
                    spec.transferFroms[i].amount,
                    totalWellEpochRewards,
                    0.1e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            // check OP
            if (
                chainId == OPTIMISM_CHAIN_ID &&
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY") &&
                addresses.getAddress(spec.transferFroms[i].from) ==
                addresses.getAddress(
                    "FOUNDATION_OP_MULTISIG",
                    OPTIMISM_CHAIN_ID
                ) &&
                addresses.getAddress(spec.transferFroms[i].token) ==
                addresses.getAddress("OP", OPTIMISM_CHAIN_ID)
            ) {
                assertApproxEqRel(
                    spec.transferFroms[i].amount,
                    totalOpEpochRewards,
                    0.01e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            // check for duplications
            for (
                uint256 j = 0;
                j < externalChainActions[_chainId].transferFroms.length;
                j++
            ) {
                TransferFrom memory existingTransferFrom = externalChainActions[
                    _chainId
                ].transferFroms[j];

                require(
                    keccak256(abi.encodePacked(existingTransferFrom.to)) !=
                        keccak256("MRD_IMPL"),
                    "should not transfer funds to MRD logic contract"
                );

                require(
                    keccak256(abi.encodePacked(existingTransferFrom.to)) !=
                        keccak256("ECOSYSTEM_RESERVE_IMPL"),
                    "should not transfer funds to Ecosystem Reserve logic contract"
                );
                require(
                    keccak256(abi.encodePacked(existingTransferFrom.to)) !=
                        keccak256("STK_GOVTOKEN_IMPL"),
                    "should not transfer funds to Safety Module logic contract"
                );
            }

            if (
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
            ) {
                assertApproxEqAbs(
                    int256(spec.transferFroms[i].amount),
                    spec.stkWellEmissionsPerSecond *
                        int256(endTimeStamp - startTimeStamp),
                    1e18,
                    "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
                );
            }

            externalChainActions[_chainId].transferFroms.push(
                spec.transferFroms[i]
            );
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
                string(
                    abi.encodePacked(
                        "Transfer token ",
                        vm.getLabel(token),
                        " from ",
                        vm.getLabel(from),
                        " to ",
                        vm.getLabel(to),
                        " amount ",
                        vm.toString(transferFrom.amount / 1e18),
                        " on Moonbeam"
                    )
                )
            );
        }
        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            BridgeWell memory bridgeWell = spec.bridgeWells[i];

            address target = addresses.getAddress(
                bridgeWell.target,
                bridgeWell.network
            );

            address router = addresses.getAddress("xWELL_ROUTER");
            address well = addresses.getAddress("WELL");

            // first approve
            _pushAction(
                well,
                abi.encodeWithSignature(
                    "approve(address,uint256)",
                    router,
                    bridgeWell.amount
                ),
                string(
                    abi.encodePacked(
                        "Approve xWELL Router to spend ",
                        vm.toString(bridgeWell.amount / 1e18),
                        " ",
                        vm.getLabel(well)
                    )
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
                string(
                    abi.encodePacked(
                        "Bridge ",
                        vm.toString(bridgeWell.amount / 1e18),
                        " WELL to ",
                        vm.getLabel(target),
                        " on ",
                        bridgeWell.network.chainIdToName()
                    )
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
                string(
                    abi.encodePacked(
                        "Set reward speed for market ",
                        vm.getLabel(
                            addresses.getAddress(setRewardSpeed.market)
                        ),
                        " on Moonbeam.\nSupply speed: ",
                        vm.toString(setRewardSpeed.newSupplySpeed),
                        "\nBorrow speed: ",
                        vm.toString(setRewardSpeed.newBorrowSpeed),
                        "\nReward type: ",
                        vm.toString(setRewardSpeed.rewardType)
                    )
                ),
                ActionType.Moonbeam
            );
        }

        AddRewardInfo memory stellaSwapReward = spec.addRewardInfo;
        // first approve
        _pushAction(
            addresses.getAddress("GOVTOKEN"),
            abi.encodeWithSignature(
                "approve(address,uint256)",
                addresses.getAddress(stellaSwapReward.target),
                uint256(stellaSwapReward.amount)
            ),
            string(
                abi.encodePacked(
                    "Approve StellaSwap spend ",
                    vm.toString(uint256(stellaSwapReward.amount) / 1e18),
                    " WELL"
                )
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
            string(
                abi.encodePacked(
                    "Add reward info for pool ",
                    vm.toString(stellaSwapReward.pid),
                    " on StellaSwap.\nReward per second: ",
                    vm.toString(uint256(stellaSwapReward.rewardPerSec)),
                    "\nEnd timestamp: ",
                    vm.toString(stellaSwapReward.endTimestamp)
                )
            ),
            ActionType.Moonbeam
        );

        if (spec.stkWellEmissionsPerSecond != -1) {
            _pushAction(
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                abi.encodeWithSignature(
                    "configureAsset(uint128,address)",
                    spec.stkWellEmissionsPerSecond.toUint256().toUint128(),
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
                ),
                //"Set reward speed for the Safety Module on Moonbeam",
                string(
                    abi.encodePacked(
                        "Set reward speed for the Safety Module on Moonbeam.\nEmissions per second: ",
                        vm.toString(spec.stkWellEmissionsPerSecond)
                    )
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
                    string(
                        abi.encodePacked(
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
                    string(
                        abi.encodePacked(
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
                    )
                );
            }
        }

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetMRDRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);
            address mrd = addresses.getAddress("MRD_PROXY");

            IMultiRewardDistributor distributor = IMultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            try
                distributor.getConfigForMarket(
                    MToken(addresses.getAddress(setRewardSpeed.market)),
                    addresses.getAddress(setRewardSpeed.emissionToken)
                )
            {
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
                        string(
                            abi.encodePacked(
                                "Set reward supply speed to ",
                                vm.toString(setRewardSpeed.newSupplySpeed),
                                " for ",
                                vm.getLabel(market),
                                ".\nNetwork: ",
                                _chainId.chainIdToName(),
                                "\nReward token: ",
                                setRewardSpeed.emissionToken
                            )
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
                        string(
                            abi.encodePacked(
                                "Set reward borrow speed to ",
                                vm.toString(setRewardSpeed.newBorrowSpeed),
                                " for ",
                                vm.getLabel(market),
                                ".\nNetwork: ",
                                _chainId.chainIdToName(),
                                "\nReward token: ",
                                setRewardSpeed.emissionToken
                            )
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
                        string(
                            abi.encodePacked(
                                "Set reward end time to ",
                                vm.toString(setRewardSpeed.newEndTime),
                                " for ",
                                vm.getLabel(market),
                                ".\nNetwork:",
                                _chainId.chainIdToName(),
                                "\nReward token: ",
                                setRewardSpeed.emissionToken
                            )
                        )
                    );
                }
            } catch {
                uint256 supplySpeed = setRewardSpeed.newSupplySpeed > 0
                    ? uint256(setRewardSpeed.newSupplySpeed)
                    : 0; // initiate with default configuration
                uint256 borrowSpeed = setRewardSpeed.newBorrowSpeed > 1
                    ? uint256(setRewardSpeed.newBorrowSpeed)
                    : 1; // initiate with default configuration
                uint256 endTime = setRewardSpeed.newEndTime > 0
                    ? uint256(setRewardSpeed.newEndTime)
                    : block.timestamp + 30 days; // initiate with default configuration

                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_addEmissionConfig(address,address,address,uint256,uint256,uint256)",
                        market,
                        addresses.getAddress("TEMPORAL_GOVERNOR"),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        supplySpeed,
                        borrowSpeed,
                        endTime
                    ),
                    string(
                        abi.encodePacked(
                            "Initiate rewards for market ",
                            vm.getLabel(market),
                            " on ",
                            _chainId.chainIdToName(),
                            "\nReward token: ",
                            setRewardSpeed.emissionToken,
                            " Supply speed: ",
                            vm.toString(supplySpeed),
                            " Borrow speed: ",
                            vm.toString(borrowSpeed),
                            " End time: ",
                            vm.toString(endTime)

                        )
                    )
                );
            }
        }

        if (spec.stkWellEmissionsPerSecond != -1) {
            _pushAction(
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                abi.encodeWithSignature(
                    "configureAsset(uint128,address)",
                    spec.stkWellEmissionsPerSecond.toUint256().toUint128(),
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
                ),
                string(
                    abi.encodePacked(
                        "Set reward speed to ",
                        vm.toString(spec.stkWellEmissionsPerSecond),
                        " for the Safety Module on ",
                        _chainId.chainIdToName()
                    )
                )
            );
        }
    }

    function _validateMoonbeam(Addresses addresses) private {
        vm.selectFork(MOONBEAM_FORK_ID);

        JsonSpecMoonbeam memory spec = moonbeamActions;

        IERC20 well = IERC20(addresses.getAddress("WELL"));
        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address to = addresses.getAddress(transferFrom.to);
            if (to == addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY")) {
                //  amount must be transferred as part of the DEX rewards and
                //  bridge calls
                assertApproxEqAbs(
                    well.balanceOf(to),
                    wellBalancesBefore[to],
                    1e18,
                    "balance changed for MULTICHAIN_GOVERNOR_PROXY"
                );
            } else {
                assertEq(
                    well.balanceOf(to),
                    wellBalancesBefore[to] + transferFrom.amount,
                    string(
                        abi.encodePacked("balance wrong for ", vm.getLabel(to))
                    )
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

                uint256 expectedValue = quoteEVMDeliveryPrice * 4;

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
                    string(
                        abi.encodePacked(
                            "Supply speed for ",
                            vm.getLabel(market),
                            " is incorrect"
                        )
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
                    string(
                        abi.encodePacked(
                            "Borrow speed for ",
                            vm.getLabel(market),
                            " is incorrect"
                        )
                    )
                );
            }
        }

        {
            if (spec.stkWellEmissionsPerSecond != -1) {
                address stkGovToken = addresses.getAddress(
                    "STK_GOVTOKEN_PROXY"
                );
                // assert safety module reward speed
                IStakedWell stkWell = IStakedWell(stkGovToken);

                (uint256 emissionsPerSecond, , ) = stkWell.assets(stkGovToken);
                assertEq(
                    int256(emissionsPerSecond),
                    spec.stkWellEmissionsPerSecond,
                    "Emissions per second for the Safety Module on Moonbeam is incorrect"
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
            "StellaSwap Rewarder should not have an open allowance after execution"
        );

        // validate that stellaswap receive the correct amount of well
        assertApproxEqAbs(
            well.balanceOf(stellaSwapRewarder),
            wellBalancesBefore[stellaSwapRewarder] + addRewardInfo.amount,
            1e18,
            "StellaSwap Rewarder should have received the correct amount of WELL"
        );

        uint256 blockTimestamp = block.timestamp;

        // block.timestamp must be in the current reward period to the getter
        // functions return the correct values
        vm.warp(addRewardInfo.endTimestamp - 1);
        assertEq(
            stellaSwap.poolRewardsPerSec(addRewardInfo.pid),
            addRewardInfo.rewardPerSec,
            "Reward per second for StellaSwap is incorrect"
        );
        assertEq(
            stellaSwap.currentEndTimestamp(addRewardInfo.pid),
            addRewardInfo.endTimestamp,
            "End timestamp for StellaSwap is incorrect"
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

        // validate transfer calls
        IERC20 well = IERC20(addresses.getAddress("xWELL_PROXY"));

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            address to = addresses.getAddress(spec.transferFroms[i].to);
            address token = addresses.getAddress(spec.transferFroms[i].token);

            if (token == addresses.getAddress("xWELL_PROXY")) {
                assertEq(
                    well.balanceOf(to),
                    wellBalancesBefore[to] + spec.transferFroms[i].amount,
                    string(
                        abi.encodePacked(
                            "balance changed for ",
                            vm.getLabel(to)
                        )
                    )
                );
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
                int256(emissionsPerSecond),
                spec.stkWellEmissionsPerSecond,
                "Emissions per second for the Safety Module is incorrect"
            );
        }
        IMultiRewardDistributor distributor = IMultiRewardDistributor(
            addresses.getAddress("MRD_PROXY")
        );

        // validate setRewardSpeed calls
        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetMRDRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

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
                            string(
                                abi.encodePacked(
                                    "Supply speed for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            )
                        );
                    }

                    if (setRewardSpeed.newBorrowSpeed != -1) {
                        assertEq(
                            int256(_config.borrowEmissionsPerSec),
                            setRewardSpeed.newBorrowSpeed,
                            string(
                                abi.encodePacked(
                                    "Borrow speed for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            )
                        );
                    }

                    if (setRewardSpeed.newEndTime != -1) {
                        assertEq(
                            int256(_config.endTime),
                            setRewardSpeed.newEndTime,
                            string(
                                abi.encodePacked(
                                    "End time for ",
                                    vm.getLabel(market),
                                    " is incorrect"
                                )
                            )
                        );
                    }
                }
            }
        }
    }
}

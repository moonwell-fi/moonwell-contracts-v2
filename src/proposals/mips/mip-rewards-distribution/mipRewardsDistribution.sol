//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {mip00} from "@proposals/mips/mip00.sol";
import {MToken} from "@protocol/MToken.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface StellaSwapRewarder {
    function poolRewardsPerSec(uint256 _pid) external view returns (uint256);

    function currentEndTimestamp(uint256 _pid) external view returns (uint256);
}

contract mipRewardsDistribution is HybridProposal, Networks {
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;
    using ProposalActions for *;
    using stdStorage for StdStorage;

    struct BridgeWell {
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

    struct AddRewardInfo {
        uint256 amount;
        uint256 endTimestamp;
        uint256 pid;
        uint256 rewardPerSec;
        string target;
    }

    struct SetRewardSpeed {
        string market;
        uint256 newBorrowSpeed;
        uint256 newSupplySpeed;
        uint256 rewardType;
        string target;
    }

    struct SetMRDRewardSpeed {
        string emissionToken;
        string market;
        uint256 newBorrowSpeed;
        uint256 newEndTime;
        uint256 newSupplySpeed;
    }

    struct JsonSpecMoonbeam {
        AddRewardInfo addRewardInfo;
        BridgeWell[] bridgeWells;
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    struct JsonSpecExternalChain {
        SetMRDRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    JsonSpecMoonbeam moonbeamActions;

    mapping(uint256 chainid => JsonSpecExternalChain) externalChainActions;

    /// we need to save this value to check if the transferFrom amount was successfully transferred
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

        _saveMoonbeamActions(addresses, encodedJson);

        // mock relayer so we can simulate bridging well
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter();
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        // we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
        // call it must switch forks
        wormholeRelayer.setIsMultichainTest(true);

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
            uint256 chainId = networks[i].chainId;
            // skip moonbeam
            if (chainId == MOONBEAM_CHAIN_ID) {
                continue;
            }

            vm.selectFork(chainId.toForkId());

            _saveExternalChainActions(addresses, encodedJson, chainId);

            // stores the wormhole mock address in the wormholeRelayer variable
            vm.store(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                bytes32(uint256(153)),
                encodedData
            );

            // save well balances before so we can check if the transferFrom was successful
            IERC20 xwell = IERC20(addresses.getAddress("xWELL_PROXY"));

            address mrd = addresses.getAddress("MRD_PROXY");
            wellBalancesBefore[mrd] = xwell.balanceOf(mrd);

            address dexRelayer = addresses.getAddress("DEX_RELAYER");
            wellBalancesBefore[dexRelayer] = xwell.balanceOf(dexRelayer);
        }

        // TODO remove this once o00  gets executed
        mip00 o00 = new mip00();
        vm.makePersistent(address(o00));
        vm.selectFork(o00.primaryForkId());
        o00.initProposal(addresses);
        o00.preBuildMock(addresses);
        o00.build(addresses);
        o00.run(addresses, address(this));

        vm.selectFork(primaryForkId());

        {
            // stores the wormhole mock address in the wormholeRelayer variable
            vm.store(
                address(wormholeBridgeAdapter),
                bytes32(uint256(153)),
                encodedData
            );

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
    }

    function build(Addresses addresses) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            if (chainId == MOONBEAM_CHAIN_ID) {
                _buildMoonbeamActions(addresses);
            } else {
                _buildExternalChainActions(addresses, chainId);
            }
        }
    }

    function validate(Addresses addresses, address) public override {
        for (uint256 i = 0; i < networks.length; i++) {
            uint256 chainId = networks[i].chainId;
            if (chainId == MOONBEAM_CHAIN_ID) {
                _validateMoonbeam(addresses);
            } else {
                _validateExternalChainActions(addresses, chainId);
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
        moonbeamActions.stkWellEmissionsPerSecond = spec
            .stkWellEmissionsPerSecond;

        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            moonbeamActions.bridgeWells.push(spec.bridgeWells[i]);
        }

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

            moonbeamActions.setRewardSpeed.push(setRewardSpeed);
        }

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            // check for duplications
            for (uint256 j = 0; j < moonbeamActions.transferFroms.length; j++) {
                TransferFrom memory existingTransferFrom = moonbeamActions
                    .transferFroms[j];

                require(
                    addresses.getAddress(existingTransferFrom.token) !=
                        addresses.getAddress(spec.transferFroms[i].token) ||
                        addresses.getAddress(existingTransferFrom.from) !=
                        addresses.getAddress(spec.transferFroms[i].from) ||
                        addresses.getAddress(spec.transferFroms[i].to) !=
                        addresses.getAddress(existingTransferFrom.to),
                    "Duplication in transferFroms"
                );
            }

            moonbeamActions.transferFroms.push(spec.transferFroms[i]);
        }
    }

    function _saveExternalChainActions(
        Addresses addresses,
        string memory data,
        uint256 chainId
    ) private {
        string memory chain = string.concat(".", vm.toString(chainId));

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecExternalChain memory spec = abi.decode(
            parsedJson,
            (JsonSpecExternalChain)
        );

        externalChainActions[chainId].stkWellEmissionsPerSecond = spec
            .stkWellEmissionsPerSecond;

        uint256 totalEpochRewards = 0;

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            // check for duplications
            for (
                uint256 j = 0;
                j < externalChainActions[chainId].setRewardSpeed.length;
                j++
            ) {
                SetMRDRewardSpeed
                    memory existingSetRewardSpeed = externalChainActions[
                        chainId
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

            assertGe(
                spec.setRewardSpeed[i].newBorrowSpeed,
                1,
                "Borrow speed must be greater or equal to 1"
            );

            uint256 supplyAmount = spec.setRewardSpeed[i].newSupplySpeed *
                (block.timestamp + spec.setRewardSpeed[i].newEndTime);

            uint256 borrowAmount = spec.setRewardSpeed[i].newBorrowSpeed *
                (block.timestamp + spec.setRewardSpeed[i].newEndTime);

            totalEpochRewards += supplyAmount + borrowAmount;

            externalChainActions[chainId].setRewardSpeed.push(
                spec.setRewardSpeed[i]
            );
        }

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            if (
                addresses.getAddress(spec.transferFroms[i].to) ==
                addresses.getAddress("MRD_PROXY")
            ) {
                assertApproxEqRel(
                    spec.transferFroms[i].amount,
                    totalEpochRewards,
                    0.1e18,
                    "Transfer amount must be close to the total rewards for the epoch"
                );
            }

            // check for duplications
            for (
                uint256 j = 0;
                j < externalChainActions[chainId].transferFroms.length;
                j++
            ) {
                TransferFrom memory existingTransferFrom = externalChainActions[
                    chainId
                ].transferFroms[j];

                require(
                    addresses.getAddress(existingTransferFrom.token) !=
                        addresses.getAddress(spec.transferFroms[i].token) ||
                        addresses.getAddress(existingTransferFrom.from) !=
                        addresses.getAddress(spec.transferFroms[i].from) ||
                        addresses.getAddress(spec.transferFroms[i].to) !=
                        addresses.getAddress(existingTransferFrom.to),
                    "Duplication in transferFroms"
                );
            }

            externalChainActions[chainId].transferFroms.push(
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

            uint16 wormholeChainId = bridgeWell.network.toWormholeChainId();

            uint256 bridgeCost = xWELLRouter(router).bridgeCost(
                wormholeChainId
            ) * 20; // make sure that the proposal does not revert due to bridge
            // cost changing

            _pushAction(
                router,
                bridgeCost,
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

        _pushAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                spec.stkWellEmissionsPerSecond,
                addresses.getAddress("STK_GOVTOKEN")
            ),
            "Set reward speed for the Safety Module on Moonbeam",
            ActionType.Moonbeam
        );

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            _pushAction(
                addresses.getAddress(setRewardSpeed.target),
                abi.encodeWithSignature(
                    "_setRewardSpeed(uint8,address,uint256,uint256)",
                    uint8(setRewardSpeed.rewardType),
                    addresses.getAddress(setRewardSpeed.market),
                    setRewardSpeed.newSupplySpeed,
                    setRewardSpeed.newBorrowSpeed
                ),
                string(
                    abi.encodePacked(
                        "Set reward speed for market ",
                        vm.getLabel(
                            addresses.getAddress(setRewardSpeed.market)
                        ),
                        " on Moonbeam. Supply speed: ",
                        vm.toString(setRewardSpeed.newSupplySpeed),
                        " Borrow speed: ",
                        vm.toString(setRewardSpeed.newBorrowSpeed)
                    )
                ),
                ActionType.Moonbeam
            );
        }

        AddRewardInfo memory addRewardInfo = spec.addRewardInfo;

        // first approve
        _pushAction(
            addresses.getAddress("GOVTOKEN"),
            abi.encodeWithSignature(
                "approve(address,uint256)",
                addresses.getAddress(addRewardInfo.target),
                addRewardInfo.amount
            ),
            string(
                abi.encodePacked(
                    "Approve StellaSwap spend ",
                    vm.toString(addRewardInfo.amount / 1e18),
                    " WELL"
                )
            ),
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress(addRewardInfo.target),
            abi.encodeWithSignature(
                "addRewardInfo(uint256,uint256,uint256)",
                addRewardInfo.pid,
                addRewardInfo.endTimestamp,
                addRewardInfo.rewardPerSec
            ),
            string(
                abi.encodePacked(
                    "Add reward info for pool ",
                    vm.toString(addRewardInfo.pid),
                    " on StellaSwap. Reward per second: ",
                    vm.toString(addRewardInfo.rewardPerSec),
                    " End timestamp: ",
                    vm.toString(addRewardInfo.endTimestamp)
                )
            ),
            ActionType.Moonbeam
        );
    }

    function _buildExternalChainActions(
        Addresses addresses,
        uint256 chainId
    ) private {
        vm.selectFork(chainId.toForkId());

        JsonSpecExternalChain memory spec = externalChainActions[chainId];

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            TransferFrom memory transferFrom = spec.transferFroms[i];

            address token = addresses.getAddress(transferFrom.token);
            address from = addresses.getAddress(transferFrom.from);
            address to = addresses.getAddress(transferFrom.to);

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
                        chainId.chainIdToName()
                    )
                )
            );
        }

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetMRDRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);

            address mrd = addresses.getAddress("MRD_PROXY");

            IMultiRewardDistributor distributor = IMultiRewardDistributor(
                addresses.getAddress("MRD_PROXY")
            );

            IMultiRewardDistributor.MarketConfig
                memory emissionConfig = distributor.getConfigForMarket(
                    MToken(addresses.getAddress(setRewardSpeed.market)),
                    addresses.getAddress(setRewardSpeed.emissionToken)
                );

            // only update if the values are different or the configuration exists
            if (
                emissionConfig.supplyEmissionsPerSec !=
                setRewardSpeed.newSupplySpeed
            ) {
                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_updateSupplySpeed(address,address,uint256)",
                        addresses.getAddress(setRewardSpeed.market),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        setRewardSpeed.newSupplySpeed
                    ),
                    string(
                        abi.encodePacked(
                            "Set reward supply speed to ",
                            vm.toString(setRewardSpeed.newSupplySpeed),
                            " for ",
                            vm.getLabel(market),
                            " on ",
                            chainId.chainIdToName()
                        )
                    )
                );
            }

            if (
                emissionConfig.borrowEmissionsPerSec !=
                setRewardSpeed.newBorrowSpeed
            ) {
                _pushAction(
                    mrd,
                    abi.encodeWithSignature(
                        "_updateBorrowSpeed(address,address,uint256)",
                        addresses.getAddress(setRewardSpeed.market),
                        addresses.getAddress(setRewardSpeed.emissionToken),
                        setRewardSpeed.newBorrowSpeed
                    ),
                    string(
                        abi.encodePacked(
                            "Set reward borrow speed to ",
                            vm.toString(setRewardSpeed.newBorrowSpeed),
                            " for ",
                            vm.getLabel(market),
                            " on ",
                            chainId.chainIdToName()
                        )
                    )
                );
            }

            if (emissionConfig.endTime != 0) {
                // new end time must be greater than the current end time
                assertGt(
                    setRewardSpeed.newEndTime,
                    emissionConfig.endTime,
                    "New end time must be greater than the current end time"
                );

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
                            " on ",
                            chainId.chainIdToName()
                        )
                    )
                );
            }
        }

        _pushAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                spec.stkWellEmissionsPerSecond,
                addresses.getAddress("STK_GOVTOKEN")
            ),
            string(
                abi.encodePacked(
                    "Set reward speed to ",
                    vm.toString(spec.stkWellEmissionsPerSecond),
                    " for the Safety Module on ",
                    chainId.chainIdToName()
                )
            )
        );
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
                assertEq(
                    well.balanceOf(to),
                    wellBalancesBefore[to],
                    "balance changed for MULTICHAIN_GOVERNOR_PROXY"
                );
            } else {
                assertEq(
                    well.balanceOf(to),
                    wellBalancesBefore[to] + transferFrom.amount,
                    string(
                        abi.encodePacked(
                            "balance changed for ",
                            vm.getLabel(to)
                        )
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

        address stkGovToken = addresses.getAddress("STK_GOVTOKEN");

        // assert safety module reward speed
        IStakedWell stkWell = IStakedWell(stkGovToken);
        (uint256 emissionsPerSecond, , ) = stkWell.assets(stkGovToken);
        assertEq(emissionsPerSecond, spec.stkWellEmissionsPerSecond);

        // validate setRewardSpeed calls
        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);

            ComptrollerInterfaceV1 comptrollerV1 = ComptrollerInterfaceV1(
                addresses.getAddress("UNITROLLER")
            );
            assertEq(
                comptrollerV1.supplyRewardSpeeds(
                    uint8(setRewardSpeed.rewardType),
                    address(market)
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

            assertEq(
                comptrollerV1.borrowRewardSpeeds(
                    uint8(setRewardSpeed.rewardType),
                    address(market)
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

        // validate dex rewards
        AddRewardInfo memory addRewardInfo = spec.addRewardInfo;

        address stellaSwapRewarder = addresses.getAddress(
            "STELLASWAP_REWARDER"
        );
        StellaSwapRewarder stellaSwap = StellaSwapRewarder(stellaSwapRewarder);

        // check allowance
        assertEq(
            well.allowance(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                stellaSwapRewarder
            ),
            0,
            "StellaSwap Rewarder should not have an open allowance after execution"
        );

        // validate that stellaswap receive the correct amount of well
        assertEq(
            well.balanceOf(stellaSwapRewarder),
            wellBalancesBefore[stellaSwapRewarder] + addRewardInfo.amount,
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
        uint256 chainId
    ) private {
        vm.selectFork(chainId.toForkId());

        JsonSpecExternalChain memory spec = externalChainActions[chainId];

        // validate transfer calls
        IERC20 well = IERC20(addresses.getAddress("xWELL_PROXY"));

        for (uint256 i = 0; i < spec.transferFroms.length; i++) {
            address to = addresses.getAddress(spec.transferFroms[i].to);
            assertEq(
                well.balanceOf(to),
                wellBalancesBefore[to] + spec.transferFroms[i].amount,
                string(
                    abi.encodePacked("balance changed for ", vm.getLabel(to))
                )
            );
        }

        {
            // validate emissions per second for the Safety Module
            IStakedWell stkWell = IStakedWell(
                addresses.getAddress("STK_GOVTOKEN")
            );

            (uint256 emissionsPerSecond, , ) = stkWell.assets(
                addresses.getAddress("STK_GOVTOKEN")
            );
            assertEq(
                emissionsPerSecond,
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
                    assertEq(
                        _config.supplyEmissionsPerSec,
                        setRewardSpeed.newSupplySpeed,
                        string(
                            abi.encodePacked(
                                "Supply speed for ",
                                vm.getLabel(market),
                                " is incorrect"
                            )
                        )
                    );
                    assertEq(
                        _config.borrowEmissionsPerSec,
                        setRewardSpeed.newBorrowSpeed,
                        string(
                            abi.encodePacked(
                                "Borrow speed for ",
                                vm.getLabel(market),
                                " is incorrect"
                            )
                        )
                    );
                    assertEq(
                        _config.endTime,
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

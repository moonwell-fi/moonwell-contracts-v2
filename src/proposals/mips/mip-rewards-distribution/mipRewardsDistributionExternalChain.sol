//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {MToken} from "@protocol/MToken.sol";
import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IWormholeRelayer} from "@protocol/wormhole/IWormholeRelayer.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {IMultiRewardDistributor} from "@protocol/rewards/IMultiRewardDistributor.sol";
import {IERC20Metadata as IERC20} from "@openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface StellaSwapRewarder {
    function poolRewardsPerSec(uint256 _pid) external view returns (uint256);

    function currentEndTimestamp(uint256 _pid) external view returns (uint256);
}

contract mipRewardsDistributionExternalChain is HybridProposal, Networks {
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

    struct SetMRDRewardSpeed {
        string emissionToken;
        string market;
        uint256 newBorrowSpeed;
        uint256 newEndTime;
        uint256 newSupplySpeed;
    }

    struct JsonSpecMoonbeam {
        BridgeWell[] bridgeWells;
        TransferFrom[] transferFroms;
    }

    struct JsonSpecExternalChain {
        SetMRDRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    JsonSpecMoonbeam moonbeamActions;

    mapping(uint256 chainid => JsonSpecExternalChain) externalChainActions;

    uint256 chainId;
    uint256 startTimeStamp;
    uint256 endTimeStamp;

    /// we need to save this value to check if the transferFrom amount was successfully transferred
    mapping(address => uint256) public wellBalancesBefore;

    modifier mockHook(Addresses addresses) {
        _beforeSimulationHook(addresses);
        _;
        _afterSimulationHook(addresses);
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);

        chainId = uint256(vm.envUint("CHAIN_ID"));
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

        vm.selectFork(chainId.toForkId());

        _saveExternalChainActions(addresses, encodedJson, chainId);

        // save well balances before so we can check if the transferFrom was successful
        IERC20 xwell = IERC20(addresses.getAddress("xWELL_PROXY"));
        address mrd = addresses.getAddress("MRD_PROXY");
        wellBalancesBefore[mrd] = xwell.balanceOf(mrd);

        address dexRelayer = addresses.getAddress("DEX_RELAYER");
        wellBalancesBefore[dexRelayer] = xwell.balanceOf(dexRelayer);

        address reserve = addresses.getAddress("ECOSYSTEM_RESERVE_PROXY");
        wellBalancesBefore[reserve] = xwell.balanceOf(reserve);

        vm.selectFork(primaryForkId());

        {
            // save well balances before so we can check if the transferFrom was successful
            IERC20 well = IERC20(addresses.getAddress("GOVTOKEN"));

            address governor = addresses.getAddress(
                "MULTICHAIN_GOVERNOR_PROXY"
            );
            wellBalancesBefore[governor] = well.balanceOf(governor);
        }

        _saveMoonbeamActions(addresses, encodedJson);
    }

    function run(
        Addresses addresses,
        address
    ) public virtual override mockHook(addresses) {
        super.run(addresses, address(0));
    }

    function build(Addresses addresses) public override {
        _buildMoonbeamActions(addresses);
        _buildExternalChainActions(addresses, chainId);
    }

    function validate(Addresses addresses, address) public override {
        _validateMoonbeam(addresses);
        _validateExternalChainActions(addresses, chainId);
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

        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            moonbeamActions.bridgeWells.push(spec.bridgeWells[i]);
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
        uint256 _chainId
    ) private {
        string memory chain = string.concat(".", vm.toString(_chainId));

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecExternalChain memory spec = abi.decode(
            parsedJson,
            (JsonSpecExternalChain)
        );

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

        externalChainActions[_chainId].stkWellEmissionsPerSecond = spec
            .stkWellEmissionsPerSecond;

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

            assertGe(
                spec.setRewardSpeed[i].newBorrowSpeed,
                1,
                "Borrow speed must be greater or equal to 1"
            );

            if (
                addresses.getAddress(spec.setRewardSpeed[i].emissionToken) ==
                addresses.getAddress("xWELL_PROXY")
            ) {
                uint256 supplyAmount = spec.setRewardSpeed[i].newSupplySpeed *
                    (spec.setRewardSpeed[i].newEndTime - startTimeStamp);

                uint256 borrowAmount = spec.setRewardSpeed[i].newBorrowSpeed *
                    (spec.setRewardSpeed[i].newEndTime - startTimeStamp);

                totalWellEpochRewards += supplyAmount + borrowAmount;
            }

            // TODO add USDC assertion in the future
            if (
                chainId == OPTIMISM_CHAIN_ID &&
                addresses.getAddress(spec.setRewardSpeed[i].emissionToken) ==
                addresses.getAddress("OP", OPTIMISM_CHAIN_ID)
            ) {
                totalOpEpochRewards +=
                    spec.setRewardSpeed[i].newSupplySpeed *
                    (spec.setRewardSpeed[i].newEndTime - startTimeStamp);
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
                    0.01e18,
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
                    addresses.getAddress(existingTransferFrom.token) !=
                        addresses.getAddress(spec.transferFroms[i].token) ||
                        addresses.getAddress(existingTransferFrom.from) !=
                        addresses.getAddress(spec.transferFroms[i].from) ||
                        addresses.getAddress(spec.transferFroms[i].to) !=
                        addresses.getAddress(existingTransferFrom.to),
                    "Duplication in transferFroms"
                );

                require(
                    keccak256(abi.encodePacked(existingTransferFrom.to)) !=
                        keccak256("MULTI_REWARD_DISTRIBUTOR"),
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
                    spec.transferFroms[i].amount,
                    spec.stkWellEmissionsPerSecond *
                        (endTimeStamp - startTimeStamp),
                    1e9,
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

            uint16 wormholeChainId = bridgeWell.network.toWormholeChainId();
            console.log("wormhole chain id bridge well", wormholeChainId);

            console.log(
                "xwell router bridge cost",
                xWELLRouter(router).bridgeCost(wormholeChainId)
            );
            uint256 bridgeCost = xWELLRouter(router).bridgeCost(
                wormholeChainId
            ) * 4; // make sure that the proposal does not revert due to bridge
            // cost changing

            console.log("bridge cost", bridgeCost);

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

            if (
                chainId == OPTIMISM_CHAIN_ID &&
                from ==
                addresses.getAddress(
                    "FOUNDATION_OP_MULTISIG",
                    OPTIMISM_CHAIN_ID
                )
            ) {
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
                            _chainId.chainIdToName()
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
                            _chainId.chainIdToName()
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
                            _chainId.chainIdToName()
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
                    _chainId.chainIdToName()
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
                // TODO remove the ApproxEqRel once we get the final values from the worker
                assertApproxEqAbs(
                    well.balanceOf(to),
                    wellBalancesBefore[to],
                    0.01e18,
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

        // assert bridgeToRecipient value is correct
        xWELLRouter router = xWELLRouter(addresses.getAddress("xWELL_ROUTER"));

        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        IWormholeRelayer relayer = IWormholeRelayer(
            addresses.getAddress("WORMHOLE_BRIDGE_RELAYER")
        );

        (uint256 quoteEVMDeliveryPrice, ) = relayer.quoteEVMDeliveryPrice(
            chainId.toWormholeChainId(),
            0,
            gasLimit
        );

        uint256 expectedValue = quoteEVMDeliveryPrice * 4;

        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            BridgeWell memory bridgeWell = spec.bridgeWells[i];

            uint16 wormholeChainId = bridgeWell.network.toWormholeChainId();

            assertEq(
                router.bridgeCost(wormholeChainId),
                expectedValue,
                "Bridge cost is incorrect"
            );
        }

        // check that the actions with value has the expectedValue
        for (uint256 i = 0; i < actions.length; i++) {
            if (actions[i].value != 0) {
                assertEq(
                    actions[i].value,
                    expectedValue,
                    "Value is incorrect for action"
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

    function _beforeSimulationHook(Addresses addresses) private {
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

        vm.selectFork(chainId.toForkId());

        // stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(primaryForkId());

        // stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );
    }

    function _afterSimulationHook(Addresses addresses) private {
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        bytes32 encodedData = bytes32(
            (uint256(
                uint160(addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"))
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
}

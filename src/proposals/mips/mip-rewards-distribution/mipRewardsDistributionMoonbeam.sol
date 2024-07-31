//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {Networks} from "@proposals/utils/Networks.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ComptrollerInterfaceV1} from "@protocol/views/ComptrollerInterfaceV1.sol";
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
    }

    struct JsonSpecMoonbeam {
        AddRewardInfo addRewardInfo;
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    JsonSpecMoonbeam moonbeamActions;

    uint256 startTimeStamp;
    uint256 endTimeStamp;

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

        string memory filter = ".startTimeStamp";

        bytes memory parsedJson = vm.parseJson(encodedJson, filter);

        startTimeStamp = abi.decode(parsedJson, (uint256));

        filter = ".endTimeSTamp";

        parsedJson = vm.parseJson(encodedJson, filter);

        endTimeStamp = abi.decode(parsedJson, (uint256));

        _saveMoonbeamActions(addresses, encodedJson);

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
    }

    function build(Addresses addresses) public override {
        _buildMoonbeamActions(addresses);
    }

    function validate(Addresses addresses, address) public override {
        _validateMoonbeam(addresses);
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

            uint256 supplyAmount = spec.setRewardSpeed[i].newSupplySpeed *
                (endTimeStamp - startTimeStamp);

            uint256 borrowAmount = spec.setRewardSpeed[i].newBorrowSpeed *
                (endTimeStamp - startTimeStamp);

            totalEpochRewards += supplyAmount + borrowAmount;

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
                assertApproxEqAbs(
                    spec.transferFroms[i].amount,
                    spec.stkWellEmissionsPerSecond *
                        (endTimeStamp - startTimeStamp),
                    1e9,
                    "Amount transferred to ECOSYSTEM_RESERVE_PROXY must be equal to the stkWellEmissionsPerSecond * the epoch duration"
                );
            }

            moonbeamActions.transferFroms.push(spec.transferFroms[i]);
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
        _pushAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                spec.stkWellEmissionsPerSecond,
                addresses.getAddress("STK_GOVTOKEN")
            ),
            //"Set reward speed for the Safety Module on Moonbeam",
            string(
                abi.encodePacked(
                    "Set reward speed for the Safety Module on Moonbeam. Emissions per second: ",
                    vm.toString(spec.stkWellEmissionsPerSecond)
                )
            ),
            ActionType.Moonbeam
        );
        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];
            _pushAction(
                addresses.getAddress("UNITROLLER"),
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
                        vm.toString(setRewardSpeed.newBorrowSpeed),
                        " Reward type: ",
                        vm.toString(setRewardSpeed.rewardType)
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
                uint256(addRewardInfo.amount)
            ),
            string(
                abi.encodePacked(
                    "Approve StellaSwap spend ",
                    vm.toString(uint256(addRewardInfo.amount) / 1e18),
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
                    vm.toString(uint256(addRewardInfo.rewardPerSec)),
                    " End timestamp: ",
                    vm.toString(addRewardInfo.endTimestamp)
                )
            ),
            ActionType.Moonbeam
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
                assertApproxEqAbs(
                    well.balanceOf(to),
                    wellBalancesBefore[to],
                    1e18, // tolerates 1 well as margin error
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
        // check allowance tolerating a dust wei amount
        assertApproxEqAbs(
            well.allowance(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                stellaSwapRewarder
            ),
            0,
            1e8, // 0.00000001e18 well
            "StellaSwap Rewarder should not have an open allowance after execution"
        );

        // validate that stellaswap receive the correct amount of well
        assertApproxEqAbs(
            well.balanceOf(stellaSwapRewarder),
            wellBalancesBefore[stellaSwapRewarder] + addRewardInfo.amount,
            1e8, // 0.00000001e18 well
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
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract mipRewardsDistribution is Test, HybridProposal {
    using String for string;
    using stdJson for string;
    using ChainIds for uint256;

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

    struct JsonSpecMoonbeam {
        AddRewardInfo addRewardInfo;
        BridgeWell[] bridgeWells;
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    struct JsonSpecBase {
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile(vm.envString("DESCRIPTION_PATH"))
        );

        _setProposalDescription(proposalDescription);
    }

    function build(Addresses addresses) public override {
        string memory data = vm.readFile(vm.envString("MIP_REWARDS_PATH"));

        buildMoonbeamActions(addresses, data);
    }

    function name() external pure override returns (string memory) {
        return "MIP Rewards Distribution";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function validate(Addresses, address) public override {}

    function buildMoonbeamActions(
        Addresses addresses,
        string memory data
    ) private {
        string memory chain = ".1284";

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecMoonbeam memory spec = abi.decode(
            parsedJson,
            (JsonSpecMoonbeam)
        );

        buildTransferFroms(addresses, spec.transferFroms);

        // Next actions must be the bridge well calls
        //  for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
        //      BridgeWell memory bridgeWell = spec.bridgeWells[i];

        //      address target = addresses.getAddress(
        //          bridgeWell.target,
        //          bridgeWell.network
        //      );

        //      address router = addresses.getAddress("xWELL_ROUTER");
        //  }

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

        // set reward speed
        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);

            _pushAction(
                market,
                abi.encodeWithSignature(
                    "_setRewardSpeed(uint8, address, uint256,uint256)",
                    uint8(setRewardSpeed.rewardType),
                    addresses.getAddress(setRewardSpeed.market),
                    setRewardSpeed.newBorrowSpeed,
                    setRewardSpeed.newSupplySpeed
                ),
                "Set reward speed for the Moonwell Markets on Moonbeam",
                ActionType.Moonbeam
            );
        }

        AddRewardInfo memory addRewardInfo = spec.addRewardInfo;

        _pushAction(
            addresses.getAddress(addRewardInfo.target),
            abi.encodeWithSignature(
                "addRewardInfo(uint256,,uint256,uint256)",
                addRewardInfo.pid,
                addRewardInfo.endTimestamp,
                addRewardInfo.rewardPerSec
            ),
            "Add reward info for the Moonwell Markets on Moonbeam",
            ActionType.Moonbeam
        );
    }

    function buildBaseAction(Addresses addresses, string memory data) private {
        string memory chain = ".1284";

        bytes memory parsedJson = vm.parseJson(data, chain);

        JsonSpecBase memory spec = abi.decode(parsedJson, (JsonSpecBase));

        buildTransferFroms(addresses, spec.transferFroms);

        for (uint256 i = 0; i < spec.setRewardSpeed.length; i++) {
            SetRewardSpeed memory setRewardSpeed = spec.setRewardSpeed[i];

            address market = addresses.getAddress(setRewardSpeed.market);

            _pushAction(
                market,
                abi.encodeWithSignature(
                    "setRewardSpeed(uint256,uint256,uint256)",
                    setRewardSpeed.newBorrowSpeed,
                    setRewardSpeed.newSupplySpeed,
                    setRewardSpeed.rewardType
                ),
                "Set reward speed for the Safety Module on Base",
                ActionType.Base
            );
        }

        _pushAction(
            addresses.getAddress("STK_GOVTOKEN"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                spec.stkWellEmissionsPerSecond,
                addresses.getAddress("STK_GOVTOKEN")
            ),
            "Set reward speed for the Safety Module on Base",
            ActionType.Base
        );
    }

    function buildTransferFroms(
        Addresses addresses,
        TransferFrom[] memory transferFroms
    ) private {
        for (uint256 i = 0; i < transferFroms.length; i++) {
            TransferFrom memory transferFrom = transferFroms[i];

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
                    abi.encode(
                        "Transfer token %s from %s to %s",
                        token,
                        from,
                        to
                    )
                )
            );
        }
    }
}

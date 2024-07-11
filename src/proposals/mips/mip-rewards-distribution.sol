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

    struct JsonSpec {
        AddRewardInfo addRewardInfo;
        BridgeWell[] bridgeWells;
        SetRewardSpeed[] setRewardSpeed;
        uint256 stkWellEmissionsPerSecond;
        TransferFrom[] transferFroms;
    }

    mapping(uint256 chainId => JsonSpec) public chainSpecs;

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

        JsonSpec memory spec = abi.decode(parsedJson, (JsonSpec));

        // First actions must be the transferFrom calls
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
                    abi.encode(
                        "Transfer token %s from %s to %s",
                        token,
                        from,
                        to
                    )
                ),
                ActionType.Moonbeam
            );
        }

        // Next actions must be the bridge well calls
        for (uint256 i = 0; i < spec.bridgeWells.length; i++) {
            BridgeWell memory bridgeWell = spec.bridgeWells[i];

            address target = addresses.getAddress(
                bridgeWell.target,
                bridgeWell.network
            );

            address router = addresses.getAddress("xWELL_ROUTER");
        }
    }
}

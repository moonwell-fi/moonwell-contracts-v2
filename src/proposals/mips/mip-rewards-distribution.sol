//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

contract mipRewardsDistribution is Test, HybridProposal {
    using stdJson for string;

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
        uint256 newSupplySpeed;
        uint256 newBorrowSpeed;
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

    constructor() {
        string memory data = vm.readFile(vm.envString("MIP_REWARDS_PATH"));

        string[] memory chains = new string[](1);
        chains[0] = ".8453";

        for (uint i = 0; i < chains.length; i++) {
            bytes memory parsedJson = vm.parseJson(data, chains[i]);

            JsonSpec memory spec = abi.decode(parsedJson, (JsonSpec));
        }
    }

    function name() external view override returns (string memory) {
        return "MIP Rewards Distribution";
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function validate(Addresses, address) public override {}
}

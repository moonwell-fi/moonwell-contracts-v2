//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import "@forge-std/StdJson.sol";
import "@protocol/utils/ChainIds.sol";
import "@protocol/utils/String.sol";

import {SafeCast} from "@openzeppelin-contracts/contracts/utils/math/SafeCast.sol";

import {MErc20} from "@protocol/MErc20.sol";
import {MToken} from "@protocol/MToken.sol";
import {OPTIMISM_CHAIN_ID} from "@utils/ChainIds.sol";
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

contract VaultRewardsDistributionTemplate is HybridProposal, Networks {
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
    // 7: Morpho Campaign
    uint32 constant CAMPAIGN_TYPE = 7;
    address rewardToken;
    address from;
    address to;
    uint256 amount;
    uint32 duration;
    uint32 startTimestamp;

    function initProposal(Addresses addresses) public override {
        rewardToken = addresses.getAddress("xWELL_PROXY");
        from = addresses.getAddress("TEMPORAL_GOVERNOR");
        to = addresses.getAddress("ANGLE_CAMPAIGN_CREATOR");
        amount = 1e18;
        duration = 60 days;
        startTimestamp = uint32(block.timestamp);

        vm.startPrank(addresses.getAddress("FOUNDATION_MULTISIG"));
        IERC20(rewardToken).approve(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            amount
        );
        vm.stopPrank();
    }

    function name() public pure override returns (string memory) {
        return "Vault Rewards Distribution";
    }

    function primaryForkId() public view override returns (uint256) {
        return vm.envUint("FORK_ID");
    }

    function build(Addresses addresses) public override {
        vm.selectFork(primaryForkId());

        _pushAction(
            rewardToken,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                from,
                to,
                amount
            ),
            string.concat(
                "Transfer token ",
                vm.getLabel(rewardToken),
                " from ",
                vm.getLabel(from),
                " to ",
                vm.getLabel(to),
                " amount ",
                vm.toString(amount / 1e18)
            )
        );

        // approve Angle Campaign Creator to spend the reward token
        _pushAction(
            rewardToken,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                addresses.getAddress("ANGLE_CAMPAIGN_CREATOR"),
                amount
            ),
            string.concat(
                "Approve ",
                vm.getLabel(rewardToken),
                " to ",
                vm.getLabel(addresses.getAddress("ANGLE_CAMPAIGN_CREATOR"))
            )
        );

        // call acceptConditions() on Angle Campaign Creator
        _pushAction(
            addresses.getAddress("ANGLE_CAMPAIGN_CREATOR"),
            abi.encodeWithSignature("acceptConditions()"),
            "Accept conditions on Angle Campaign Creator"
        );

        // now create a campaign
        /* 

*/

        bytes32 campaignId = bytes32(0);
        address creator = address(0);
        bytes memory campaignData = "";

        CampaignParameters memory newCampaign = CampaignParameters({
            campaignId: campaignId,
            creator: creator,
            rewardToken: rewardToken,
            amount: amount,
            campaignType: CAMPAIGN_TYPE,
            startTimestamp: startTimestamp,
            duration: duration,
            campaignData: campaignData
        });

        bytes memory encoded = abi.encodeWithSignature(
            "createCampaign(tuple(bytes32,address,address,uint256,uint32,uint32,uint32,bytes))",
            (newCampaign)
        );

        _pushAction(
            addresses.getAddress("ANGLE_CAMPAIGN_CREATOR"),
            encoded,
            "Create campaign"
        );
    }

    function validate(Addresses addresses, address) public override {}
}

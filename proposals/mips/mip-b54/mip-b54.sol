//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import "@protocol/utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";

import {xWELLRouter} from "@protocol/xWELL/xWELLRouter.sol";

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

/// @title MIP-B54: Moonwell Morpho Vault Incentive Campaigns (Excluding meUSDC)
/// @notice Proposal to create vault incentive campaigns with same APY as MIP-X40
///         for USDC, WETH, EURC, and cbBTC MetaMorpho vaults until February 2nd.
/// @dev This proposal:
///      1. Bridges xWELL tokens from Moonbeam to Base
///      2. Creates Merkle campaigns for 4 MetaMorpho vaults (excluding meUSDC)
///      3. Maintains same reward rate (APY) as MIP-X40 campaigns
contract mipb54 is HybridProposal, Configs {
    using ChainIds for uint256;

    /// @notice the name of the proposal
    string public constant override name = "MIP-B54";

    // ============ Campaign Timing Configuration ============
    // Campaign starts exactly when X40 vault incentives end
    // X40 vault campaigns started: Jan 2, 2026 13:30:18 UTC (1767360618)
    // X40 vault campaign duration: 14 days (1,209,600 seconds)
    // X40 vault campaigns end: Jan 16, 2026 13:30:18 UTC (1768570218)
    // B54 ends: February 2nd, 2026 00:00:00 UTC (1769990400)
    uint32 public constant CAMPAIGN_START_TIMESTAMP = 1768570218; // When X40 vaults end (Jan 16, 2026 13:30:18)
    uint32 public constant CAMPAIGN_END_TIMESTAMP = 1769990400; // Feb 2, 2026 00:00:00 UTC
    uint32 public constant CAMPAIGN_DURATION =
        CAMPAIGN_END_TIMESTAMP - CAMPAIGN_START_TIMESTAMP; // ~16.44 days (1,420,182 sec)

    // ============ APY Maintenance Calculation ============
    // X40 vault campaigns used 14-day duration (1,209,600 seconds)
    // To maintain same APY (reward per second), we scale amounts proportionally:
    // new_amount = x40_amount * (new_duration / x40_duration)

    uint256 public constant X40_VAULT_DURATION = 1209600; // 14 days in seconds

    // X40 original amounts (14 days):
    // USDC: 1.1551917839192369e24, WETH: 3.869502356298615e23
    // EURC: 2.3087682693661858e23, cbBTC: 9.44995881527945e22
    // Scaled amounts for new duration (maintaining same APY)
    uint256 public constant USDC_AMOUNT =
        (1155191783919236900000000 * CAMPAIGN_DURATION) / X40_VAULT_DURATION;
    uint256 public constant WETH_AMOUNT =
        (386950235629861500000000 * CAMPAIGN_DURATION) / X40_VAULT_DURATION;
    uint256 public constant EURC_AMOUNT =
        (230876826936618580000000 * CAMPAIGN_DURATION) / X40_VAULT_DURATION;
    uint256 public constant cbBTC_AMOUNT =
        (94499588152794500000000 * CAMPAIGN_DURATION) / X40_VAULT_DURATION;

    // Total tokens needed for all vault campaigns
    uint256 public constant TOTAL_CAMPAIGN_AMOUNT =
        USDC_AMOUNT + WETH_AMOUNT + EURC_AMOUNT + cbBTC_AMOUNT;

    // Amount to bridge from Moonbeam (same as total campaign amount)
    uint256 public constant BRIDGE_AMOUNT = TOTAL_CAMPAIGN_AMOUNT;

    // Campaign type for MORPHOVAULT incentives
    uint32 public constant MORPHOVAULT_CAMPAIGN_TYPE = 56;

    // ============ Campaign Data (Vault Addresses Encoded) ============
    // Each campaign data contains the vault address as the first 32 bytes

    // USDC MetaMorpho Vault: 0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca
    bytes public constant CAMPAIGN_DATA_USDC =
        hex"000000000000000000000000c1256ae5ff1cf2719d4937adb3bbccab2e00a2ca0000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    // WETH MetaMorpho Vault: 0xa0E430870c4604CcfC7B38Ca7845B1FF653D0ff1
    bytes public constant CAMPAIGN_DATA_WETH =
        hex"000000000000000000000000a0e430870c4604ccfc7b38ca7845b1ff653d0ff10000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    // EURC MetaMorpho Vault: 0xf24608E0CCb972b0b0f4A6446a0BBf58c701a026
    bytes public constant CAMPAIGN_DATA_EURC =
        hex"000000000000000000000000f24608e0ccb972b0b0f4a6446a0bbf58c701a0260000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    // cbBTC MetaMorpho Vault: 0x543257eF2161176D7C8cD90BA65C2d4CaEF5a796
    bytes public constant CAMPAIGN_DATA_CBBTC =
        hex"000000000000000000000000543257ef2161176d7c8cd90ba65c2d4caef5a7960000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000012000000000000000000000000000000000000000000000000000000000000001400000000000000000000000000000000000000000000000000000000000000160000000000000000000000000000000000000000000000000000000000000018000000000000000000000000000000000000000000000000000000000000001a000000000000000000000000000000000000000000000000000000000000001c00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-b54/b54.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        // Mock relayer for cross-chain bridging simulation
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter(
            new uint16[](0),
            new uint256[](0)
        );
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        // Approve governor to spend WELL tokens for bridging
        vm.startPrank(addresses.getAddress("F-GLMR-DEVGRANT"));
        IERC20(addresses.getAddress("GOVTOKEN")).approve(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            BRIDGE_AMOUNT
        );
        vm.stopPrank();

        vm.selectFork(primaryForkId());

        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );
    }

    function build(Addresses addresses) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        address router = addresses.getAddress("xWELL_ROUTER");
        address well = addresses.getAddress("GOVTOKEN");

        // Step 1: Transfer WELL from dev grant to governor
        _pushAction(
            well,
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("F-GLMR-DEVGRANT"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                BRIDGE_AMOUNT
            ),
            "Transfer WELL from F-GLMR-DEVGRANT to MULTICHAIN_GOVERNOR_PROXY"
        );

        // Step 2: Approve xWELL Router to spend WELL for bridging
        _pushAction(
            well,
            abi.encodeWithSignature(
                "approve(address,uint256)",
                router,
                BRIDGE_AMOUNT
            ),
            string(
                abi.encodePacked(
                    "Approve xWELL Router to spend ",
                    vm.toString(BRIDGE_AMOUNT / 1e18),
                    " WELL"
                )
            ),
            ActionType.Moonbeam
        );

        uint16 wormholeChainId = BASE_CHAIN_ID.toWormholeChainId();
        uint256 bridgeCost = xWELLRouter(router).bridgeCost(wormholeChainId);

        // Step 3: Bridge xWELL to Base Temporal Governor
        _pushAction(
            router,
            bridgeCost,
            abi.encodeWithSignature(
                "bridgeToRecipient(address,uint256,uint16)",
                addresses.getAddress("TEMPORAL_GOVERNOR", BASE_CHAIN_ID),
                BRIDGE_AMOUNT,
                wormholeChainId
            ),
            "Bridge xWELL to TEMPORAL_GOVERNOR on Base",
            ActionType.Moonbeam
        );

        vm.selectFork(BASE_FORK_ID);

        // Step 4: Approve Merkle Campaign Creator to spend xWELL
        _pushAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "approve(address,uint256)",
                addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
                TOTAL_CAMPAIGN_AMOUNT
            ),
            "Approve Merkle Campaign Creator for vault campaigns"
        );

        // Step 5: Accept Merkle conditions
        _pushAction(
            addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
            abi.encodeWithSignature("acceptConditions()"),
            "Accept Merkle Campaign Creator conditions"
        );

        // Step 6: Create campaigns for each vault (excluding meUSDC)
        _createCampaign(addresses, "USDC", USDC_AMOUNT, CAMPAIGN_DATA_USDC);
        _createCampaign(addresses, "WETH", WETH_AMOUNT, CAMPAIGN_DATA_WETH);
        _createCampaign(addresses, "EURC", EURC_AMOUNT, CAMPAIGN_DATA_EURC);
        _createCampaign(addresses, "cbBTC", cbBTC_AMOUNT, CAMPAIGN_DATA_CBBTC);
    }

    function _createCampaign(
        Addresses addresses,
        string memory assetName,
        uint256 campaignAmount,
        bytes memory campaignData
    ) internal {
        IMerkleCampaignCreator.CampaignParameters
            memory campaign = IMerkleCampaignCreator.CampaignParameters({
                campaignId: bytes32(0),
                creator: address(0),
                rewardToken: addresses.getAddress("xWELL_PROXY"),
                amount: campaignAmount,
                campaignType: MORPHOVAULT_CAMPAIGN_TYPE,
                startTimestamp: CAMPAIGN_START_TIMESTAMP,
                duration: CAMPAIGN_DURATION,
                campaignData: campaignData
            });

        _pushAction(
            addresses.getAddress("MERKLE_CAMPAIGN_CREATOR"),
            abi.encodeWithSignature(
                "createCampaign((bytes32,address,address,uint256,uint32,uint32,uint32,bytes))",
                campaign.campaignId,
                campaign.creator,
                campaign.rewardToken,
                campaign.amount,
                campaign.campaignType,
                campaign.startTimestamp,
                campaign.duration,
                campaign.campaignData
            ),
            string(
                abi.encodePacked(
                    "Create ",
                    assetName,
                    " MetaMorpho vault campaign"
                )
            )
        );
    }

    function validate(Addresses addresses, address) public override {
        string[4] memory vaultNames = [
            "USDC_METAMORPHO_VAULT",
            "WETH_METAMORPHO_VAULT",
            "EURC_METAMORPHO_VAULT",
            "cbBTC_METAMORPHO_VAULT"
        ];

        string[4] memory assetNames = ["USDC", "WETH", "EURC", "cbBTC"];

        uint256[4] memory vaultAmounts = [
            USDC_AMOUNT,
            WETH_AMOUNT,
            EURC_AMOUNT,
            cbBTC_AMOUNT
        ];

        bytes[4] memory campaignDatas = [
            CAMPAIGN_DATA_USDC,
            CAMPAIGN_DATA_WETH,
            CAMPAIGN_DATA_EURC,
            CAMPAIGN_DATA_CBBTC
        ];

        for (uint256 i = 0; i < vaultNames.length; i++) {
            IMerkleCampaignCreator.CampaignParameters
                memory campaignParams = IMerkleCampaignCreator
                    .CampaignParameters({
                        campaignId: bytes32(0),
                        creator: addresses.getAddress("TEMPORAL_GOVERNOR"),
                        rewardToken: addresses.getAddress("xWELL_PROXY"),
                        amount: vaultAmounts[i],
                        campaignType: MORPHOVAULT_CAMPAIGN_TYPE,
                        startTimestamp: CAMPAIGN_START_TIMESTAMP,
                        duration: CAMPAIGN_DURATION,
                        campaignData: campaignDatas[i]
                    });

            bytes32 campaignId = IMerkleCampaignCreator(
                addresses.getAddress("MERKLE_CAMPAIGN_CREATOR")
            ).campaignId(campaignParams);

            assertNotEq(
                campaignId,
                bytes32(0),
                string(
                    abi.encodePacked(
                        assetNames[i],
                        " vault campaign should be created"
                    )
                )
            );
        }
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Configs} from "@proposals/Configs.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

/*
DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRE_BUILD_MOCK=true DO_BUILD=true \
DO_RUN=true DO_VALIDATE=true forge script src/proposals/mips/mip-x01/mip-x01.sol:mipx01 \
 -vvv
*/
contract mipx01 is HybridProposal, Configs {
    using ChainIds for uint256;
    using ProposalActions for *;

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for Optimism
    uint128 public constant distributionDuration = 100 * 365 days;

    /// @notice approval amount for ecosystem reserve to give stkWELL in xWELL xD
    uint256 public constant approvalAmount = 5_000_000_000 * 1e18;

    /// @notice end of distribution period for stkWELL
    uint256 public constant DISTRIBUTION_END = 4874349773;

    string public constant override name =
        "MIP-X01: xWELL and Multichain Governor Upgrade";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-x01/MIP-X01.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        /// upgrade the multichain governor on Moonbeam
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL")
            ),
            "Upgrade the Multichain Governor implementation on Moonbeam",
            ActionType.Moonbeam
        );

        /// update xWELL implementation across both Moonbeam and Base
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("xWELL_LOGIC")
            ),
            "Upgrade the xWELL implementation on Moonbeam",
            ActionType.Moonbeam
        );

        uint256 baseChainId = block.chainid.toBaseChainId();
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN", baseChainId),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY", baseChainId),
                addresses.getAddress("xWELL_LOGIC", baseChainId)
            ),
            "Upgrade the xWELL implementation on Base",
            ActionType.Base
        );

        /// upgrade the multichain vote collection on Base
        _pushAction(
            addresses.getAddress("MRD_PROXY_ADMIN", baseChainId),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("VOTE_COLLECTION_PROXY", baseChainId),
                addresses.getAddress("VOTE_COLLECTION_IMPL", baseChainId)
            ),
            "Upgrade the Multichain Vote Collection implementation on Base",
            ActionType.Base
        );

        vm.selectFork(OPTIMISM_FORK_ID);

        {
            WormholeTrustedSender.TrustedSender[]
                memory voteCollectionTrustedSender = new WormholeTrustedSender.TrustedSender[](
                    1
                );
            voteCollectionTrustedSender[0] = WormholeTrustedSender
                .TrustedSender(
                    OPTIMISM_WORMHOLE_CHAIN_ID,
                    addresses.getAddress("VOTE_COLLECTION_PROXY")
                );

            /// Add Optimism Vote Collection contract to the MultichainGovernor
            /// as a trusted sender
            _pushAction(
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                abi.encodeWithSignature(
                    "addExternalChainConfigs((uint16,address)[])",
                    voteCollectionTrustedSender
                ),
                "Add Vote Collection on Optimism to Target Address in Multichain Governor",
                ActionType.Moonbeam
            );
        }

        /// open up rate limits to move tokens across all chains

        {
            WormholeTrustedSender.TrustedSender[]
                memory optimismWormholeBridgeAdapter = new WormholeTrustedSender.TrustedSender[](
                    1
                );
            optimismWormholeBridgeAdapter[0] = WormholeTrustedSender
                .TrustedSender(
                    OPTIMISM_WORMHOLE_CHAIN_ID,
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                );

            /// Add moonbeam -> optimism xWELL route
            _pushAction(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                abi.encodeWithSignature(
                    "addTrustedSenders((uint16,address)[])",
                    optimismWormholeBridgeAdapter
                ),
                "Add xWELL route from Moonbeam to Optimism in trusted sender mapping",
                ActionType.Moonbeam
            );
            _pushAction(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                abi.encodeWithSignature(
                    "setTargetAddresses((uint16,address)[])",
                    optimismWormholeBridgeAdapter
                ),
                "Add xWELL route from Moonbeam to Optimism in target address mapping",
                ActionType.Moonbeam
            );

            _pushAction(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toBaseChainId()
                ),
                abi.encodeWithSignature(
                    "addTrustedSenders((uint16,address)[])",
                    optimismWormholeBridgeAdapter
                ),
                "Add xWELL route from Base to Optimism in trusted sender mapping",
                ActionType.Base
            );
            _pushAction(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toBaseChainId()
                ),
                abi.encodeWithSignature(
                    "setTargetAddresses((uint16,address)[])",
                    optimismWormholeBridgeAdapter
                ),
                "Add xWELL route from Base to Optimism in target address mapping",
                ActionType.Base
            );
        }
    }

    function run(Addresses addresses, address) public override {
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 4,
            "MIP-O01: should have 4 base actions"
        );
        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 5,
            "MIP-O01: should have 5 moonbeam actions"
        );
        require(
            actions.proposalActionTypeCount(ActionType.Optimism) == 0,
            "MIP-O01: should have 0 optimism actions"
        );

        super.run(addresses, address(0));
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        /// check that the xWELL implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("xWELL_LOGIC"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam xWELL_PROXY validation"
        );
        /// check that the Multichain Governor implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam MULTICHAIN_GOVERNOR_IMPL validation"
        );

        /// validate multichain governor contract
        {
            MultichainGovernor governor = MultichainGovernor(
                payable(addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"))
            );

            uint16[] memory chains = governor.getAllTargetChains();
            bool found = false;
            for (uint256 i = 0; i < chains.length; i++) {
                if (
                    chains[i] ==
                    block.chainid.toOptimismChainId().toWormholeChainId()
                ) {
                    found = true;
                    break;
                }
            }

            assertEq(
                governor.getAllTargetChainsLength(),
                2,
                "incorrect number of target chains"
            );
            assertEq(chains.length, 2, "incorrect number of target chains");
            assertTrue(
                found,
                "optimism wormhole chain not found in target chains"
            );
            assertEq(
                governor.targetAddress(
                    block.chainid.toOptimismChainId().toWormholeChainId()
                ),
                addresses.getAddress(
                    "VOTE_COLLECTION_PROXY",
                    block.chainid.toOptimismChainId()
                ),
                "Multichain governor on Moonbeam should trust vote collection on optimism"
            );
        }

        /// validate xWELL routes on Moonbeam

        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// validate that Moonbeam bridges to Optimism
        assertEq(
            adapter.targetAddress(
                block.chainid.toOptimismChainId().toWormholeChainId()
            ),
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                block.chainid.toOptimismChainId()
            ),
            "incorrect target address for bridge adapter on moonbeam to Optimism"
        );

        assertEq(
            adapter
                .allTrustedSenders(
                    block.chainid.toOptimismChainId().toWormholeChainId()
                )
                .length,
            1,
            "incorrect number of Optimism trusted senders"
        );
        assertEq(
            adapter
                .allTrustedSenders(block.chainid.toBaseWormholeChainId())
                .length,
            1,
            "incorrect number of Base trusted senders"
        );
        assertTrue(
            adapter.isTrustedSender(
                block.chainid.toOptimismChainId().toWormholeChainId(),
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toOptimismChainId()
                )
            ),
            "Optimism vote collection not a trusted sender on Moonbeam"
        );

        vm.selectFork(BASE_FORK_ID);

        /// check that the xWELL implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("xWELL_LOGIC"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "Base xWELL_PROXY validation"
        );
        /// check that the Multichain Vote Collection implementation has been successfully changed
        validateProxy(
            vm,
            addresses.getAddress("VOTE_COLLECTION_PROXY"),
            addresses.getAddress("VOTE_COLLECTION_IMPL"),
            addresses.getAddress("MRD_PROXY_ADMIN"),
            "Base VOTE_COLLECTION_PROXY validation"
        );

        adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        /// validate that Base bridges to Optimism
        assertEq(
            adapter.targetAddress(
                block.chainid.toOptimismChainId().toWormholeChainId()
            ),
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                block.chainid.toOptimismChainId()
            ),
            "incorrect target address for bridge adapter on Base to Optimism"
        );

        assertEq(
            adapter.targetAddress(block.chainid.toMoonbeamWormholeChainId()),
            addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                block.chainid.toMoonbeamChainId()
            ),
            "incorrect target address for bridge adapter on Base to Moonbeam"
        );
        assertTrue(
            adapter.isTrustedSender(
                block.chainid.toMoonbeamWormholeChainId(),
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toMoonbeamChainId()
                )
            ),
            "Moonbeam wormhole bridge adapter not a trusted sender on Base"
        );

        assertEq(
            adapter
                .allTrustedSenders(block.chainid.toMoonbeamWormholeChainId())
                .length,
            1,
            "incorrect number of moonbeam trusted senders"
        );

        assertEq(
            adapter
                .allTrustedSenders(
                    block.chainid.toOptimismChainId().toWormholeChainId()
                )
                .length,
            1,
            "incorrect number of optimism trusted senders"
        );

        assertTrue(
            adapter.isTrustedSender(
                block.chainid.toOptimismChainId().toWormholeChainId(),
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toOptimismChainId()
                )
            ),
            "Optimism vote collection not a trusted sender on Base"
        );

        vm.selectFork(OPTIMISM_FORK_ID);

        /// proxy validation
        {
            validateProxy(
                vm,
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "vote collection validation"
            );

            validateProxy(
                vm,
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
                addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "ecosystem reserve validation"
            );

            validateProxy(
                vm,
                addresses.getAddress("STK_GOVTOKEN"),
                addresses.getAddress("STK_GOVTOKEN_IMPL"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "STK_GOVTOKEN validation"
            );

            validateProxy(
                vm,
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("xWELL_LOGIC"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "xWELL_PROXY validation"
            );
        }

        /// ecosystem reserve and controller
        {
            IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                    addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
                );

            assertEq(
                ecosystemReserveController.owner(),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "ecosystem reserve controller owner not set correctly"
            );
            assertEq(
                ecosystemReserveController.ECOSYSTEM_RESERVE(),
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
                "ecosystem reserve controller not pointing to ECOSYSTEM_RESERVE_PROXY"
            );
            assertTrue(
                ecosystemReserveController.initialized(),
                "ecosystem reserve not initialized"
            );

            IEcosystemReserveUplift ecosystemReserve = IEcosystemReserveUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY")
            );

            assertEq(
                ecosystemReserve.getFundsAdmin(),
                address(ecosystemReserveController),
                "ecosystem reserve funds admin not set correctly"
            );

            xWELL xWell = xWELL(addresses.getAddress("xWELL_PROXY"));

            assertEq(
                xWell.allowance(
                    address(ecosystemReserve),
                    addresses.getAddress("STK_GOVTOKEN")
                ),
                approvalAmount,
                "ecosystem reserve not approved to give stkWELL_PROXY approvalAmount"
            );

            ecosystemReserve = IEcosystemReserveUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_IMPL")
            );
            assertEq(
                ecosystemReserve.getFundsAdmin(),
                address(1),
                "funds admin on impl incorrect"
            );
        }

        /// validate stkWELL contract
        {
            IStakedWellUplift stkWell = IStakedWellUplift(
                addresses.getAddress("STK_GOVTOKEN")
            );

            {
                (
                    uint128 emissionsPerSecond,
                    uint128 lastUpdateTimestamp,

                ) = stkWell.assets(address(stkWell));

                assertEq(emissionsPerSecond, 0, "emissionsPerSecond incorrect");
                assertEq(lastUpdateTimestamp, 0, "lastUpdateTimestamp set");
            }

            /// stake and reward token are the same
            assertEq(
                stkWell.STAKED_TOKEN(),
                addresses.getAddress("xWELL_PROXY"),
                "incorrect staked token"
            );
            assertEq(
                stkWell.REWARD_TOKEN(),
                addresses.getAddress("xWELL_PROXY"),
                "incorrect reward token"
            );

            assertEq(
                stkWell.REWARDS_VAULT(),
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
                "incorrect rewards vault, not ECOSYSTEM_RESERVE_PROXY"
            );
            assertEq(
                stkWell.UNSTAKE_WINDOW(),
                unstakeWindow,
                "incorrect unstake window"
            );
            assertEq(
                stkWell.COOLDOWN_SECONDS(),
                cooldownSeconds,
                "incorrect cooldown seconds"
            );
            assertEq(
                stkWell.DISTRIBUTION_END(),
                DISTRIBUTION_END,
                "incorrect distribution duration"
            );
            assertEq(
                stkWell.EMISSION_MANAGER(),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "incorrect emissions manager"
            );
            assertEq(
                stkWell._governance(),
                address(0),
                "incorrect _governance, not address(0)"
            );
            assertEq(stkWell.name(), "Staked WELL", "incorrect stkWell name");
            assertEq(stkWell.symbol(), "stkWELL", "incorrect stkWell symbol");
            assertEq(stkWell.decimals(), 18, "incorrect stkWell decimals");
            assertEq(
                stkWell.totalSupply(),
                0,
                "incorrect stkWell starting total supply"
            );
        }

        /// validate vote collection contract
        {
            MultichainVoteCollection voteCollection = MultichainVoteCollection(
                addresses.getAddress("VOTE_COLLECTION_PROXY")
            );

            assertEq(
                address(voteCollection.xWell()),
                addresses.getAddress("xWELL_PROXY"),
                "incorrect xWELL"
            );

            assertEq(
                address(voteCollection.stkWell()),
                addresses.getAddress("STK_GOVTOKEN"),
                "incorrect stkWELL"
            );

            assertEq(
                address(voteCollection.wormholeRelayer()),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "incorrect WORMHOLE_BRIDGE_RELAYER address"
            );

            assertEq(
                voteCollection.owner(),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "incorrect vote collection owner, not temporal governor"
            );
            assertEq(
                voteCollection.getAllTargetChains().length,
                1,
                "incorrect target chain length"
            );
            assertEq(
                voteCollection.getAllTargetChains()[0],
                block.chainid.toMoonbeamWormholeChainId(),
                "incorrect target chain, not moonbeam"
            );
            assertEq(
                voteCollection.gasLimit(),
                400_000,
                "incorrect gas limit on vote collection contract"
            );

            assertEq(
                voteCollection.targetAddress(
                    block.chainid.toMoonbeamWormholeChainId()
                ),
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                "target address not multichain governor on moonbeam"
            );

            assertTrue(
                voteCollection.isTrustedSender(
                    block.chainid.toMoonbeamWormholeChainId(),
                    addresses.getAddress(
                        "MULTICHAIN_GOVERNOR_PROXY",
                        block.chainid.toMoonbeamChainId()
                    )
                ),
                "multichain governor not trusted sender in vote collection"
            );
        }

        vm.selectFork(primaryForkId());
    }
}

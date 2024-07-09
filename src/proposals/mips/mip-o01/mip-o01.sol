//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import "@utils/ChainIds.sol";

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {Configs} from "@proposals/Configs.sol";
import {
    ActionType,
    HybridProposal
} from "@proposals/proposalTypes/HybridProposal.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";

import {WormholeTrustedSender} from
    "@protocol/governance/WormholeTrustedSender.sol";
import {MultichainGovernorDeploy} from
    "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {MultichainVoteCollection} from
    "@protocol/governance/multichain/MultichainVoteCollection.sol";

import {
    IEcosystemReserveControllerUplift,
    IEcosystemReserveUplift
} from "@protocol/stkWell/IEcosystemReserveUplift.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";

/*
DO_DEPLOY=true DO_AFTER_DEPLOY=true DO_PRE_BUILD_MOCK=true DO_BUILD=true \
DO_RUN=true DO_VALIDATE=true forge script src/proposals/mips/mip-o01/mip-o01.sol:mipo01 \
 -vvv
*/

/// NONCE ORDER:
/// - 473 xWELL Logic
/// - 474 Wormhole Bridge Adapter Logic
/// - 475 xWELL Proxy
/// - 476 Wormhole Bridge Adapter Proxy

/// use deployBaseSystem for xWELL and xWELL Bridge Adapter Deployment

/// TODO deploy xWELL and WORMHOLE_BRIDGE_ADAPTER's outside of this proposal
/// TODO deployment script should open Optimism -> Moonbeam route in the constructor

/// TODO write an integration test after this proposal for this proposal specifically to check
/// - rate limits across chains are equal
/// - wormhole bridge adapters across chains all trust each other
/// - stkWELL contracts have no reward speeds set
/// - xERC20 contract works as expected and only has a single trusted bridge on each chain
contract mipo01 is Configs, HybridProposal, MultichainGovernorDeploy {
    using ChainIds for uint256;
    using ProposalActions for *;

    string public constant override name = "MIP-O01";

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for Optimism
    uint128 public constant distributionDuration = 100 * 365 days;

    /// @notice approval amount for ecosystem reserve to give stkWELL in xWELL xD
    uint256 public constant approvalAmount = 5_000_000_000 * 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-o01/MIP-O01.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return OPTIMISM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("STK_GOVTOKEN", block.chainid)) {
            address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

            /// deploy both EcosystemReserve and EcosystemReserve Controller + their corresponding proxies
            (
                address ecosystemReserveProxy,
                address ecosystemReserveImplementation,
                address ecosystemReserveController
            ) = deployEcosystemReserve(proxyAdmin);

            addresses.addAddress(
                "ECOSYSTEM_RESERVE_PROXY", ecosystemReserveProxy
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_IMPL", ecosystemReserveImplementation
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_CONTROLLER", ecosystemReserveController
            );

            {
                (address stkWellProxy, address stkWellImpl) = deployStakedWell(
                    addresses.getAddress("xWELL_PROXY"),
                    addresses.getAddress("xWELL_PROXY"),
                    cooldownSeconds,
                    unstakeWindow,
                    ecosystemReserveProxy,
                    /// check that emissions manager on Moonbeam is the Artemis Timelock, so on Base it should be the temporal governor
                    addresses.getAddress("TEMPORAL_GOVERNOR"),
                    distributionDuration,
                    address(0),
                    /// stop error on beforeTransfer hook in ERC20WithSnapshot
                    proxyAdmin
                );
                addresses.addAddress("STK_GOVTOKEN", stkWellProxy);
                addresses.addAddress("STK_GOVTOKEN_IMPL", stkWellImpl);
            }
        }

        if (!addresses.isAddressSet("VOTE_COLLECTION_PROXY")) {
            (address collectionProxy, address collectionImpl) =
            deployVoteCollection(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("STK_GOVTOKEN"),
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                block.chainid.toMoonbeamWormholeChainId(),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );

            addresses.addAddress("VOTE_COLLECTION_PROXY", collectionProxy);
            addresses.addAddress("VOTE_COLLECTION_IMPL", collectionImpl);
        }

        if (!addresses.isAddressSet("NEW_XWELL_IMPL")) {
            xWELL newImpl = new xWELL();
            addresses.addAddress("NEW_XWELL_IMPL", address(newImpl));
        }
    }

    function afterDeploy(Addresses addresses, address deployer)
        public
        override
    {
        IEcosystemReserveControllerUplift ecosystemReserveController =
        IEcosystemReserveControllerUplift(
            addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
        );

        assertEq(
            ecosystemReserveController.owner(), deployer, "incorrect owner"
        );
        assertEq(
            address(ecosystemReserveController.ECOSYSTEM_RESERVE()),
            address(0),
            "ECOSYSTEM_RESERVE set when it should not be"
        );

        address ecosystemReserve =
            addresses.getAddress("ECOSYSTEM_RESERVE_PROXY");

        /// set the ecosystem reserve
        ecosystemReserveController.setEcosystemReserve(ecosystemReserve);

        /// approve stkWELL contract to spend xWELL from the ecosystem reserve contract
        ecosystemReserveController.approve(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("STK_GOVTOKEN"),
            approvalAmount
        );

        /// transfer ownership of the ecosystem reserve controller to the temporal governor
        ecosystemReserveController.transferOwnership(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        IEcosystemReserveUplift ecosystemReserveContract =
        IEcosystemReserveUplift(addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"));

        /// take ownership of the ecosystem reserve impl to prevent any further changes or hijacking
        ecosystemReserveContract.initialize(address(1));
    }

    function preBuildMock(Addresses) public override {}

    function teardown(Addresses, address) public override {}

    /// run this action through the Artemis Governor
    function build(Addresses addresses) public override {
        {
            WormholeTrustedSender.TrustedSender[] memory
                voteCollectionTrustedSender =
                    new WormholeTrustedSender.TrustedSender[](1);
            voteCollectionTrustedSender[0] = WormholeTrustedSender.TrustedSender(
                OPTIMISM_WORMHOLE_CHAIN_ID,
                addresses.getAddress("VOTE_COLLECTION_PROXY")
            );

            /// Add OP vote collection to the MultichainGovernor
            _pushAction(
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    block.chainid.toMoonbeamChainId()
                ),
                abi.encodeWithSignature(
                    "addExternalChainConfigs((uint16,address)[])",
                    voteCollectionTrustedSender
                ),
                "Add Vote Collection on Optimism to Target Addresses",
                ActionType.Moonbeam
            );
        }

        /// update xWELL implementation across both Moonbeam and Base
        _pushAction(
            addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN", block.chainid.toMoonbeamChainId()
            ),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("NEW_XWELL_IMPL")
            ),
            "Upgrade the xWELL implementation on Moonbeam",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress(
                "MRD_PROXY_ADMIN", block.chainid.toBaseChainId()
            ),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("NEW_XWELL_IMPL")
            ),
            "Upgrade the xWELL implementation on Base",
            ActionType.Base
        );

        /// open up rate limits to move tokens across all chains

        {
            WormholeTrustedSender.TrustedSender[] memory
                moonbeamWormholeBridgeAdapter =
                    new WormholeTrustedSender.TrustedSender[](1);
            moonbeamWormholeBridgeAdapter[0] = WormholeTrustedSender
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
                    "addExternalChainConfigs((uint16,address)[])",
                    moonbeamWormholeBridgeAdapter
                ),
                "Add xWELL route from Moonbeam to Optimism",
                ActionType.Moonbeam
            );

            _pushAction(
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    block.chainid.toBaseChainId()
                ),
                abi.encodeWithSignature(
                    "addExternalChainConfigs((uint16,address)[])",
                    moonbeamWormholeBridgeAdapter
                ),
                "Add xWELL route from Base to Optimism",
                ActionType.Base
            );
        }

        /// TODO deployment script should open
        /// Optimism -> Moonbeam + Optimism -> Base
        /// route in the constructor
        {
            WormholeTrustedSender.TrustedSender[] memory
                optimismWormholeBridgeAdapter =
                    new WormholeTrustedSender.TrustedSender[](1);

            optimismWormholeBridgeAdapter[0] = WormholeTrustedSender
                .TrustedSender(
                BASE_WORMHOLE_CHAIN_ID,
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            );
            _pushAction(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                abi.encodeWithSignature(
                    "addExternalChainConfigs((uint16,address)[])",
                    optimismWormholeBridgeAdapter
                ),
                "Add xWELL route from Optimism to Base",
                ActionType.Optimism
            );
        }
    }

    function run(Addresses addresses, address) public override {
        /// TODO update numbers once proposal changes
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-O01: should have X base actions"
        );
        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 0,
            "MIP-O01: should have X moonbeam actions"
        );
        require(
            actions.proposalActionTypeCount(ActionType.Optimism) == 0,
            "MIP-O01: should have X optimism actions"
        );

        super.run(addresses, address(0));
    }

    function validate(Addresses addresses, address) public view override {
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
                addresses.getAddress("NEW_XWELL_IMPL"),
                addresses.getAddress("MRD_PROXY_ADMIN"),
                "xWELL_PROXY validation"
            );
        }

        /// ecosystem reserve and controller
        {
            IEcosystemReserveControllerUplift ecosystemReserveController =
            IEcosystemReserveControllerUplift(
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
            IStakedWellUplift stkWell =
                IStakedWellUplift(addresses.getAddress("STK_GOVTOKEN"));

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
                block.timestamp + distributionDuration,
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
    }
}

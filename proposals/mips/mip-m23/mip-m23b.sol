//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/interfaces/IStakedWellUplift.sol";
import {BASE_FORK_ID, ChainIds} from "@utils/ChainIds.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@script/DeployMultichainGovernor.s.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/interfaces/IEcosystemReserveUplift.sol";

/// Proposal to run on Base to create the Multichain Vote Collection Contract
/// As well as the Ecosystem Reserve and Ecosystem Reserve Controller.
/// The Ecosystem Reserve Controller will be the owner of the Ecosystem Reserve
/// The Ecosystem Reserve custodies the xWELL that is used to pay rewards for
/// the safety module (stkWELL).
/// All contracts deployed are proxies.
/// to simulate: DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script
/// proposals/mips/mip-m23/mip-m23b.sol:mipm23b --fork-url base
/// to deploy: DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script
/// proposals/mips/mip-m23/mip-m23b.sol:mipm23b
/// --broadcast --slow --fork-url base
/// Once the proposal is execute, VOTE_COLLECTION_PROXY, VOTE_COLLECTION_IMPL,
/// ECOSYSTEM_RESERVE_PROXY, ECOSYSTEM_RESERVE_IMPL, STK_GOVTOKEN_PROXY, STK_GOVTOKEN_IMPL
/// and xWELL_PROXY must be added to the addresses.json file.
contract mipm23b is HybridProposal, MultichainGovernorDeploy {
    using ChainIds for uint256;

    /// @notice deployment of the Multichain Vote Collection Contract to Base
    string public constant override name = "MIP-M23B";

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for Base
    uint128 public constant distributionDuration = 100 * 365 days;

    /// @notice approval amount for ecosystem reserve to give stkWELL in xWELL xD
    uint256 public constant approvalAmount = 5_000_000_000 * 1e18;

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

        if (!addresses.isAddressSet("STK_GOVTOKEN_PROXY", block.chainid)) {
            /// deploy both EcosystemReserve and EcosystemReserve Controller + their corresponding proxies
            (
                address ecosystemReserveProxy,
                address ecosystemReserveImplementation,
                address ecosystemReserveController
            ) = deployEcosystemReserve(proxyAdmin);

            addresses.addAddress(
                "ECOSYSTEM_RESERVE_PROXY",
                ecosystemReserveProxy
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_IMPL",
                ecosystemReserveImplementation
            );
            addresses.addAddress(
                "ECOSYSTEM_RESERVE_CONTROLLER",
                ecosystemReserveController
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
                    address(0), /// stop error on beforeTransfer hook in ERC20WithSnapshot
                    proxyAdmin
                );
                addresses.addAddress("STK_GOVTOKEN_PROXY", stkWellProxy);
                addresses.addAddress("STK_GOVTOKEN_IMPL", stkWellImpl);
            }
        }

        if (!addresses.isAddressSet("VOTE_COLLECTION_PROXY", block.chainid)) {
            (
                address collectionProxy,
                address collectionImpl
            ) = deployVoteCollection(
                    addresses.getAddress("xWELL_PROXY"),
                    addresses.getAddress("STK_GOVTOKEN_PROXY"),
                    addresses.getAddress(
                        "MULTICHAIN_GOVERNOR_PROXY",
                        block.chainid.toMoonbeamChainId()
                    ), /// fetch multichain governor address on Moonbeam
                    addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"),
                    block.chainid.toMoonbeamWormholeChainId(),
                    proxyAdmin,
                    addresses.getAddress("TEMPORAL_GOVERNOR")
                );

            addresses.addAddress("VOTE_COLLECTION_PROXY", collectionProxy);
            addresses.addAddress("VOTE_COLLECTION_IMPL", collectionImpl);
        }
    }

    function afterDeploy(
        Addresses addresses,
        address deployer
    ) public override {
        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
            );

        assertEq(
            ecosystemReserveController.owner(),
            deployer,
            "incorrect owner"
        );
        assertEq(
            address(ecosystemReserveController.ECOSYSTEM_RESERVE()),
            address(0),
            "ECOSYSTEM_RESERVE set when it should not be"
        );

        address ecosystemReserve = addresses.getAddress(
            "ECOSYSTEM_RESERVE_PROXY"
        );

        /// set the ecosystem reserve
        ecosystemReserveController.setEcosystemReserve(ecosystemReserve);

        /// approve stkWELL contract to spend xWELL from the ecosystem reserve contract
        ecosystemReserveController.approve(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            approvalAmount
        );

        /// transfer ownership of the ecosystem reserve controller to the temporal governor
        ecosystemReserveController.transferOwnership(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );

        IEcosystemReserveUplift ecosystemReserveContract = IEcosystemReserveUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_IMPL")
            );

        /// take ownership of the ecosystem reserve impl to prevent any further changes or hijacking
        ecosystemReserveContract.initialize(address(1));
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
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
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
                    addresses.getAddress("STK_GOVTOKEN_PROXY")
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
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            );

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
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                "incorrect stkWELL"
            );

            assertEq(
                address(voteCollection.wormholeRelayer()),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER_PROXY"),
                "incorrect WORMHOLE_BRIDGE_RELAYER_PROXY address"
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
                "multichain governor not trusted sender"
            );
        }
    }
}

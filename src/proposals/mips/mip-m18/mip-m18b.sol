//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {MultichainVoteCollection} from "@protocol/Governance/MultichainGovernor/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

/// Proposal to run on Base to create the Multichain Vote Collection Contract
contract mipm18b is HybridProposal, MultichainGovernorDeploy, ChainIds {
    /// @notice deployment of the Multichain Vote Collection Contract to Base
    string public constant name = "MIP-M18B";

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for Base
    uint128 public constant distributionDuration = 100 * 365 days;

    /// @notice approval amount for ecosystem reserve to give stkWELL in xWELL xD
    uint256 public constant approvalAmount = 5_000_000_000 * 1e18;

    /// @notice slot for the Proxy Admin
    bytes32 _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice slot for the implementation address
    bytes32 _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function deploy(Addresses addresses, address) public override {
        address proxyAdmin = addresses.getAddress("PROXY_ADMIN");

        /// deploy both EcosystemReserve and EcosystemReserve Controller + their corresponding proxies
        (
            address ecosystemReserveProxy,
            address ecosystemReserveImplementation,
            address ecosystemReserveControllerProxy,
            address ecosystemReserveControllerImplementation
        ) = deployEcosystemReserve(proxyAdmin);

        addresses.addAddress("ECOSYSTEM_RESERVE_PROXY", ecosystemReserveProxy);
        addresses.addAddress(
            "ECOSYSTEM_RESERVE_IMPL",
            ecosystemReserveImplementation
        );
        addresses.addAddress(
            "ECOSYSTEM_RESERVE_CONTROLLER_PROXY",
            ecosystemReserveControllerProxy
        );
        addresses.addAddress(
            "ECOSYSTEM_RESERVE_CONTROLLER_IMPL",
            ecosystemReserveControllerImplementation
        );

        /// TODO check on these parameters, change `deployStakedWell` function to make temporal gov owner
        /// TODO should pass in the proxy admin here
        /// TODO should receive back both an impl, and a proxy
        {
            (address stkWellProxy, address stkWellImpl) = deployStakedWell(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("xWELL_PROXY"),
                cooldownSeconds,
                unstakeWindow,
                ecosystemReserveProxy,
                /// TODO, double check that emissions manager on Base should be temporal governor
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                /// TODO double check the distribution duration
                distributionDuration,
                address(0), /// stop error on beforeTransfer hook in ERC20WithSnapshot
                proxyAdmin
            );
            addresses.addAddress("stkWELL_PROXY", stkWellProxy);
            addresses.addAddress("stkWELL_IMPL", stkWellImpl);
        }

        (
            address collectionProxy,
            address collectionImpl
        ) = deployVoteCollection(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("stkWELL_PROXY"),
                addresses.getAddress( /// fetch multichain governor address on Moonbeam
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                chainIdToWormHoleId[block.chainid],
                proxyAdmin,
                addresses.getAddress("TEMPORAL_GOVERNOR")
            );

        addresses.addAddress("VOTE_COLLECTION_PROXY", collectionProxy);
        addresses.addAddress("VOTE_COLLECTION_IMPL", collectionImpl);
    }

    function afterDeploy(Addresses addresses, address) public override {
        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER_PROXY")
            );

        ecosystemReserveController.approve(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("stkWELL_PROXY"),
            approvalAmount
        );

        ecosystemReserveController.transferOwnership(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
    }

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {}

    function _validateProxy(
        address proxy,
        address logic,
        address admin,
        string memory error
    ) internal {
        {
            bytes32 data = vm.load(proxy, _ADMIN_SLOT);

            assertEq(
                bytes32(uint256(uint160(admin))),
                data,
                string(abi.encodePacked(error, " admin not set correctly"))
            );
        }

        {
            bytes32 data = vm.load(proxy, _IMPLEMENTATION_SLOT);

            assertEq(
                bytes32(uint256(uint160(logic))),
                data,
                string(
                    abi.encodePacked(error, " logic contract not set correctly")
                )
            );
        }
    }

    function validate(Addresses addresses, address) public override {
        /// proxy validation
        {
            _validateProxy(
                addresses.getAddress("VOTE_COLLECTION_PROXY"),
                addresses.getAddress("VOTE_COLLECTION_IMPL"),
                addresses.getAddress("PROXY_ADMIN"),
                "vote collection validation"
            );
            _validateProxy(
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
                addresses.getAddress("ECOSYSTEM_RESERVE_IMPL"),
                addresses.getAddress("PROXY_ADMIN"),
                "ecosystem reserve validation"
            );
            _validateProxy(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER_PROXY"),
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER_IMPL"),
                addresses.getAddress("PROXY_ADMIN"),
                "ecosystem reserve controller validation"
            );
            _validateProxy(
                addresses.getAddress("stkWELL_PROXY"),
                addresses.getAddress("stkWELL_IMPL"),
                addresses.getAddress("PROXY_ADMIN"),
                "stkWELL_PROXY validation"
            );
        }

        /// ecosystem reserve and controller
        {
            IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                    addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER_PROXY")
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
                    addresses.getAddress("stkWELL_PROXY")
                ),
                approvalAmount,
                "ecosystem reserve not approved to give stkWELL_PROXY approvalAmount"
            );
        }

        /// TODO validate stkWELL contract
        {
            /// smh to this architecture, do better
            IStakedWellUplift stkWell = IStakedWellUplift(
                addresses.getAddress("stkWELL_PROXY")
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

        /// TODO validate vote collection contract
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
                addresses.getAddress("stkWELL_PROXY"),
                "incorrect stkWELL"
            );

            assertEq(
                address(voteCollection.wormholeRelayer()),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "incorrect WORMHOLE_BRIDGE_RELAYER address"
            );

            assertEq(
                voteCollection.moonbeamWormholeChainId(),
                chainIdToWormHoleId[block.chainid],
                "incorrect moonbeam wormhole chainid"
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
                chainIdToWormHoleId[block.chainid],
                "incorrect target chain, not moonbeam"
            );
            assertEq(
                voteCollection.gasLimit(),
                400_000,
                "incorrect gas limit on vote collection contract"
            );

            assertEq(
                voteCollection.targetAddress(
                    chainIdToWormHoleId[block.chainid]
                ),
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    sendingChainIdToReceivingChainId[block.chainid]
                ),
                "incorrect vote collection owner, not temporal governor"
            );

            assertTrue(
                voteCollection.isTrustedSender(
                    chainIdToWormHoleId[block.chainid],
                    addresses.getAddress(
                        "MULTICHAIN_GOVERNOR_PROXY",
                        sendingChainIdToReceivingChainId[block.chainid]
                    )
                ),
                "multichain governor not trusted sender"
            );
        }
    }
}

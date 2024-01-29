//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// TODO pull in these interfaces with correct solidity version to avoid compiler error
// import {IEcosystemReserve} from "@protocol/stkWell/IEcosystemReserve.sol";

/// Proposal to run on Base to create the Multichain Vote Collection Contract
contract mipm18b is HybridProposal, MultichainGovernorDeploy, ChainIds {
    /// @notice deployment of the Multichain Vote Collection Contract to Base
    string public constant name = "MIP-M18B";

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for on Base
    uint128 public constant distributionDuration = 100 * 365 days;

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

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {}

    function validate(Addresses addresses, address) public override {
        /// TODO validate that pending owners have been set where appropriate
        /// TODO validate that new admin/owner has been set where appropriate
    }
}

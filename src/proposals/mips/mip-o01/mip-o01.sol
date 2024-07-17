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
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MultichainVoteCollection} from "@protocol/governance/multichain/MultichainVoteCollection.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

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

/// TODO write an integration test after this proposal for this proposal specifically to check
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

    /// @notice end of distribution period for stkWELL
    uint256 public constant DISTRIBUTION_END = 4874349773;

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
        if (!addresses.isAddressSet("STK_GOVTOKEN")) {
            address proxyAdmin = addresses.getAddress("MRD_PROXY_ADMIN");

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
                addresses.addAddress("STK_GOVTOKEN", stkWellProxy);
                addresses.addAddress("STK_GOVTOKEN_IMPL", stkWellImpl);
            }
        }
    }

    function afterDeploy(
        Addresses addresses,
        address deployer
    ) public override {
        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
            );

        /// skip afterDeploySetup if this step has already been completed
        if (ecosystemReserveController.owner() != deployer) {
            return;
        }

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
            addresses.getAddress("STK_GOVTOKEN"),
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

    function preBuildMock(Addresses) public override {}

    function teardown(Addresses, address) public override {}

    /// run this action through the Artemis Governor
    /// actions:
    ///
    /// - Multichain Governor - add Optimism Multichain Vote Collection as a
    /// trusted sender
    ///
    /// - xWELL - set target address and trusted sender to Optimism on Base and
    /// Moonbeam on the WormholeBridgeAdapter
    ///
    /// - stkWELL - no governance actions needed
    ///
    function build(Addresses) public override {}

    function validate(Addresses, address) public override {}
}

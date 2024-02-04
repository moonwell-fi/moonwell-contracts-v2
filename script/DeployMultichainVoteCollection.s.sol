// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {Constants} from "@protocol/Governance/MultichainGovernor/Constants.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";
import {ProxyAdmin} from "@openzeppelin-contracts/contracts/proxy/transparent/ProxyAdmin.sol";
import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

/*
 to simulate:
     forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainVoteCollectionScript \
     \ -vvvvv --rpc-url base/baseGoerli

 to run:
    forge script script/DeployMultichainVoteCollection.s.sol:DeployMultichainGovernorScript \
    \ -vvvvv --rpc-url base/baseGoerli --broadcast --etherscan-api-key base/baseGoerli --verify
*/
contract DeployMultichainVoteCollectionScript is
    Script,
    ChainIds,
    MultichainGovernorDeploy
{
    /// @notice addresses contract
    Addresses addresses;

    /// @notice deployer private key
    uint256 private PRIVATE_KEY;

    /// @notice cooldown window to withdraw staked WELL to xWELL
    uint256 public constant cooldownSeconds = 10 days;

    /// @notice unstake window for staked WELL, period of time after cooldown
    /// lapses during which staked WELL can be withdrawn for xWELL
    uint256 public constant unstakeWindow = 2 days;

    /// @notice duration that Safety Module will distribute rewards for Base
    uint128 public constant distributionDuration = 100 * 365 days;

    /// @notice approval amount for ecosystem reserve to give stkWELL in xWELL xD
    uint256 public constant approvalAmount = 5_000_000_000 * 1e18;

    constructor() {
        // Default behavior: use Anvil 0 private key
        PRIVATE_KEY = uint256(vm.envBytes32("ETH_PRIVATE_KEY"));

        addresses = new Addresses();
    }

    function run() public {
        // todo try/catch checking if address exist to make this compatible with
        // base deploy
        address proxyAdmin = address(new ProxyAdmin());

        // add base proxy admin to addresses
        addresses.addAddress("BASE_PROXY_ADMIN", proxyAdmin);

        /// deploy both EcosystemReserve and EcosystemReserve Controller + their corresponding proxies
        (
            address ecosystemReserveProxy,
            address ecosystemReserveImplementation,
            address ecosystemReserveController
        ) = deployEcosystemReserve(proxyAdmin);

        addresses.addAddress("ECOSYSTEM_RESERVE_PROXY", ecosystemReserveProxy);
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

    function afterDeploy() public {
        IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
            );

        assertEq(ecosystemReserveController.owner(), address(this), "01021");
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

        console.log("block chain id: ", block.chainid);

        /// approve stkWELL contract to spend xWELL from the ecosystem reserve contract
        ecosystemReserveController.approve(
            addresses.getAddress("xWELL_PROXY"),
            addresses.getAddress("stkWELL_PROXY"),
            approvalAmount
        );

        /// transfer ownership of the ecosystem reserve controller to the temporal governor
        ecosystemReserveController.transferOwnership(
            addresses.getAddress("TEMPORAL_GOVERNOR")
        );
    }
}

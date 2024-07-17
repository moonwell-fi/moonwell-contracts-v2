//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {Script} from "@forge-std/Script.sol";

import "@utils/ChainIds.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Configs} from "@proposals/Configs.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {IStakedWellUplift} from "@protocol/stkWell/IStakedWellUplift.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {IEcosystemReserveUplift, IEcosystemReserveControllerUplift} from "@protocol/stkWell/IEcosystemReserveUplift.sol";

contract DeploySafetyModule is Script, MultichainGovernorDeploy {
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

    function run() external {
        Addresses addresses = new Addresses();

        if (!addresses.isAddressSet("STK_GOVTOKEN")) {
            vm.startBroadcast();

            {
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
                    (
                        address stkWellProxy,
                        address stkWellImpl
                    ) = deployStakedWell(
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

            {
                IEcosystemReserveControllerUplift ecosystemReserveController = IEcosystemReserveControllerUplift(
                        addresses.getAddress("ECOSYSTEM_RESERVE_CONTROLLER")
                    );

                (, address deployer, ) = vm.readCallers();

                /// skip afterDeploySetup if this step has already been completed
                if (ecosystemReserveController.owner() != deployer) {
                    vm.stopBroadcast();
                    addresses.printAddresses();
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
                ecosystemReserveController.setEcosystemReserve(
                    ecosystemReserve
                );

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

                vm.stopBroadcast();

                addresses.printAddresses();
            }
        }

        /// validation

        /// proxy validation
        {
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
    }
}

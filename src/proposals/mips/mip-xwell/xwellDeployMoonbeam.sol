//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {Configs} from "@proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@proposals/proposalTypes/Proposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {xWELLDeploy} from "@protocol/xWELL/xWELLDeploy.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {MOONBEAM_FORK_ID} from "@utils/ChainIds.sol";

/// to run locally:
///     DO_DEPLOY=true DO_VALIDATE=true forge script src/proposals/mips/mip-xwell/xwellDeployMoonbeam.sol:xwellDeployMoonbeam --fork-url moonbeam
/// @dev do not use MIP as a base to fork off of, it will not work
contract xwellDeployMoonbeam is Proposal, Configs, xWELLDeploy, ChainIds {
    /// @notice the name of the proposal
    string public constant override name = "MIP xWELL Token Creation Moonbeam";

    /// @notice the buffer cap for the xWELL token on both base and moonbeam
    uint112 public constant bufferCap = 38_000_000 * 1e18;

    /// @notice the buffer cap for the xWELL token on moonbeam for the lockbox.
    /// Set to 10b so that all 5b WELL can be locked up and turned into xWELL tokens.
    uint112 public constant lockBoxBufferCap = 10_000_000_000 * 1e18;

    /// @notice the rate limit per second for the xWELL token on the lockbox
    uint128 public constant lockBoxRateLimitPerSecond = 0;

    /// @notice the rate limit per second for the xWELL token on both base and moonbeam
    /// heals at ~19m per day if buffer is fully replenished or depleted
    /// this limit is used for the wormhole bridge adapters
    uint128 public constant rateLimitPerSecond = 219.907 * 1e18;

    /// @notice the duration of the pause for the xWELL token on both base and moonbeam
    /// once the contract has been paused, in this period of time, it will automatically
    /// unpause if no action is taken.
    uint128 public constant pauseDuration = 10 days;

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    // @notice search for a on-chain proposal that matches the proposal calldata
    // @returns the proposal id, 0 if no proposal is found
    function getProposalId(
        Addresses,
        address
    ) public pure override returns (uint256) {
        revert("Not implemented");
    }

    function deploy(Addresses addresses, address) public override {
        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ---------------- MOONBEAM NETWORK ----------------
        /// --------------------------------------------------
        /// --------------------------------------------------

        {
            /// stkWELL proxy admin
            address existingProxyAdmin = addresses.getAddress(
                "MOONBEAM_PROXY_ADMIN"
            );

            /// pause guardian on moonbeam
            address pauseGuardian = addresses.getAddress(
                "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
            );

            /// @notice this is the address that will be own the xWELL contract
            address artemisTimelock = addresses.getAddress("MOONBEAM_TIMELOCK");

            /// @notice this is the wormhole bridge relayer the wormhole bridge adapter
            /// will plug into.
            address relayer = addresses.getAddress("WORMHOLE_BRIDGE_RELAYER");

            /// @notice the well token address
            address wellAddress = addresses.getAddress("GOVTOKEN");

            address xwellLogic;
            address xwellProxy;
            address wormholeAdapterLogic;
            address wormholeAdapter;
            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](2);

            {
                address lockbox;
                (
                    xwellLogic,
                    xwellProxy,
                    ,
                    wormholeAdapterLogic,
                    wormholeAdapter,
                    lockbox
                ) = deployMoonbeamSystem(wellAddress, existingProxyAdmin);

                limits[0].bridge = wormholeAdapter;
                limits[0].rateLimitPerSecond = rateLimitPerSecond;
                limits[0].bufferCap = bufferCap;

                limits[1].bridge = lockbox;
                limits[1].rateLimitPerSecond = lockBoxRateLimitPerSecond;
                limits[1].bufferCap = lockBoxBufferCap;

                addresses.addAddress("xWELL_LOCKBOX", lockbox);
            }

            initializeXWell(
                xwellProxy,
                "WELL",
                "WELL",
                artemisTimelock,
                limits,
                pauseDuration,
                pauseGuardian
            );

            initializeWormholeAdapter(
                wormholeAdapter,
                xwellProxy,
                artemisTimelock,
                relayer,
                uint16(chainIdToWormHoleId[block.chainid])
            );

            /// add to moonbeam addresses
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                wormholeAdapter
            );
            addresses.addAddress(
                "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                wormholeAdapterLogic
            );
            addresses.addAddress("xWELL_LOGIC", xwellLogic);
            addresses.addAddress("xWELL_PROXY", xwellProxy);

            printAddresses(addresses);
            addresses.resetRecordingAddresses();
        }
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function preBuildMock(Addresses addresses) public override {}

    /// ------------ MTOKEN MARKET ACTIVIATION BUILD ------------

    /// no cross chain proposal actions to run
    function build(Addresses addresses) public override {}

    /// no cross chain actions to run, so remove all code from this function
    /// @dev do not use MIP as a base to fork off of, it will not work
    function run(Addresses, address) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public view override {
        /// do validation for base network, then do validation for moonbeam network
        /// ensure chainId is correct and non zero
        /// ensure correct owner

        /// --------------------------------------------------
        /// --------------------------------------------------
        /// ---------------- MOONBEAM NETWORK ----------------
        /// --------------------------------------------------
        /// --------------------------------------------------
        {
            address moonbeamxWellProxy = addresses.getAddress("xWELL_PROXY");
            address wormholeBridgeAdapterProxy = addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY"
            );
            address artemisTimelock = addresses.getAddress("MOONBEAM_TIMELOCK");
            address pauseGuardian = addresses.getAddress(
                "MOONBEAM_PAUSE_GUARDIAN_MULTISIG"
            );
            address lockbox = addresses.getAddress("xWELL_LOCKBOX");

            assertEq(
                xWELL(wormholeBridgeAdapterProxy).owner(),
                artemisTimelock,
                "wormhole bridge adapter owner is incorrect"
            );
            assertEq(
                address(
                    WormholeBridgeAdapter(wormholeBridgeAdapterProxy)
                        .wormholeRelayer()
                ),
                addresses.getAddress("WORMHOLE_BRIDGE_RELAYER"),
                "wormhole bridge adapter relayer is incorrect"
            );
            assertEq(
                WormholeBridgeAdapter(wormholeBridgeAdapterProxy).gasLimit(),
                300_000,
                "wormhole bridge adapter gas limit is incorrect"
            );

            assertEq(
                xWELL(moonbeamxWellProxy).rateLimitPerSecond(
                    wormholeBridgeAdapterProxy
                ),
                rateLimitPerSecond,
                "rateLimitPerSecond is incorrect"
            );

            assertEq(
                xWELL(moonbeamxWellProxy).rateLimitPerSecond(lockbox),
                lockBoxRateLimitPerSecond,
                "lockBoxRateLimitPerSecond is incorrect"
            );
            /// ensure correct buffer cap
            assertEq(
                xWELL(moonbeamxWellProxy).bufferCap(wormholeBridgeAdapterProxy),
                bufferCap,
                "bufferCap is incorrect"
            );
            assertEq(
                xWELL(moonbeamxWellProxy).bufferCap(lockbox),
                lockBoxBufferCap,
                "lockbox bufferCap is incorrect"
            );
            assertTrue(
                WormholeBridgeAdapter(wormholeBridgeAdapterProxy)
                    .isTrustedSender(
                        uint16(chainIdToWormHoleId[block.chainid]),
                        wormholeBridgeAdapterProxy
                    ),
                "trusted sender not trusted"
            );

            assertEq(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC"),
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
                    baseChainId
                ),
                "wormhole bridge adapter logic address is not the same across chains"
            );

            assertEq(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress(
                    "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                    baseChainId
                ),
                "wormhole bridge adapter proxy address is not the same across chains"
            );

            assertEq(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("xWELL_PROXY", baseChainId),
                "xWELL_PROXY address is not the same across chains"
            );
            assertEq(
                addresses.getAddress("xWELL_LOGIC"),
                addresses.getAddress("xWELL_LOGIC", baseChainId),
                "xWELL_LOGIC address is not the same across chains"
            );

            /// ensure correct owner
            assertEq(
                xWELL(moonbeamxWellProxy).owner(),
                artemisTimelock,
                "xwell owner address is incorrect, not timelock"
            );
            assertEq(
                xWELL(moonbeamxWellProxy).pauseGuardian(),
                pauseGuardian,
                "pause guardian address is incorrect"
            );
        }
    }

    function printAddresses(Addresses addresses) private view {
        (
            string[] memory recordedNames,
            ,
            address[] memory recordedAddresses
        ) = addresses.getRecordedAddresses();
        for (uint256 j = 0; j < recordedNames.length; j++) {
            console.log("{\n        'addr': '%s', ", recordedAddresses[j]);
            console.log("        'chainId': %d,", block.chainid);
            console.log(
                "        'name': '%s'\n}%s",
                recordedNames[j],
                j < recordedNames.length - 1 ? "," : ""
            );
        }
    }

    function printCalldata(Addresses addresses) public pure override {}

    function printProposalActionSteps() public pure override {}
}

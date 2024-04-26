//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";

/// DO_VALIDATE=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-b16/mip-b16.sol:mipb16
contract mipb16 is
    HybridProposal,
    MultichainGovernorDeploy,
    ParameterValidation
{
    string public constant override name = "MIP-B16 Resubmission";

    /// @notice this is based on Warden Finance's recommendation for reward speeds
    uint256 public constant REWARD_SPEED = 896275511648961000;

    /// @notice the amount of WELL to be sent to the Safety Module for funding 38 days of rewards
    /// 36*86400*.896275511648961000 = 2,787,775.3514329283 WELL, round up to 2,787,776
    uint256 public constant WELL_AMOUNT = 2_787_776 * 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b16/MIP-B16.md")
        );

        _setProposalDescription(proposalDescription);
    }

    /// @notice proposal's actions happen only on base
    function primaryForkId() public view override returns (uint256) {
        return baseForkId;
    }

    function teardown(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        /// stop errors on unit tests of proposal infrastructure
        if (address(addresses) != address(0)) {
            vm.startPrank(addresses.getAddress("FOUNDATION_MULTISIG"));

            ERC20(addresses.getAddress("xWELL_PROXY")).approve(
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                100_000_000 * 1e18
            );

            vm.stopPrank();
        }
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Base actions

        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("FOUNDATION_MULTISIG"),
                addresses.getAddress("ECOSYSTEM_RESERVE_PROXY"),
                WELL_AMOUNT
            ),
            "Transfer xWELL rewards to Ecosystem Reserve Proxy on Base",
            false
        );

        _pushHybridAction(
            addresses.getAddress("stkWELL_PROXY"),
            abi.encodeWithSignature(
                "configureAsset(uint128,address)",
                REWARD_SPEED,
                addresses.getAddress("stkWELL_PROXY")
            ),
            "Set reward speed for the Safety Module on Base",
            false
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no moonbeam actions are run
        require(
            baseActions.length == 2,
            "MIP-B16: should have two base actions"
        );

        require(
            moonbeamActions.length == 0,
            "MIP-B16: should have no moonbeam actions"
        );
        vm.selectFork(moonbeamForkId);

        _runMoonbeamMultichainGovernor(addresses, address(1000000000));

        vm.selectFork(baseForkId);

        _runBase(addresses, addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    /// @notice validations on Base
    function validate(Addresses addresses, address) public override {
        vm.selectFork(baseForkId);

        address stkWellProxy = addresses.getAddress("stkWELL_PROXY");
        (
            uint128 emissionsPerSecond,
            uint128 lastUpdateTimestamp,

        ) = IStakedWell(stkWellProxy).assets(stkWellProxy);

        assertEq(
            emissionsPerSecond,
            REWARD_SPEED,
            "MIP-B16: emissionsPerSecond incorrect"
        );

        assertGt(
            lastUpdateTimestamp,
            0,
            "MIP-B16: lastUpdateTimestamp not set"
        );
    }
}

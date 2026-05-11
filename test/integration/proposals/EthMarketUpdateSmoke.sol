//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_FORK_ID, ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title EthMarketUpdateSmoke
/// @notice Test-only smoke proposal used by MigrationHarness to prove the
///         new Ethereum MultichainGovernorV2 can change Eth-native market
///         parameters via the full propose → vote → execute path. Bumps
///         WETH reserve factor on the freshly-deployed Eth Unitroller.
contract EthMarketUpdateSmoke is HybridProposalV2 {
    string public constant override name = "ETH-MARKET-UPDATE-SMOKE";

    /// @notice 15% reserve factor (1.5e17) - bumped from whatever mip-e00 set.
    uint256 public constant NEW_RESERVE_FACTOR = 0.15e18;

    constructor() {
        _setProposalDescription(
            abi.encodePacked("Smoke test: bump Eth WETH reserve factor")
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        vm.selectFork(ETHEREUM_FORK_ID);

        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_RESERVE_FACTOR
            ),
            "Bump Eth WETH reserve factor to 15%",
            ActionType.Ethereum
        );
    }

    function teardown(Addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            MToken(addresses.getAddress("MOONWELL_WETH"))
                .reserveFactorMantissa(),
            NEW_RESERVE_FACTOR,
            "WETH reserve factor not updated"
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_FORK_ID, BASE_FORK_ID, BASE_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title BaseMarketUpdateSmoke
/// @notice Cross-chain smoke proposal used by MigrationHarness.testPhaseF
///         to prove the new Ethereum MultichainGovernorV2 can hop through
///         Wormhole to Base TemporalGovernor and mutate a live Base
///         mToken parameter. Bumps MOONWELL_USDC reserve factor on Base.
contract BaseMarketUpdateSmoke is HybridProposalV2 {
    string public constant override name = "BASE-MARKET-UPDATE-SMOKE";

    /// @notice 12% reserve factor — distinct from EthMarketUpdateSmoke's
    /// 15% so the two smoke tests are visually disambiguable.
    uint256 public constant NEW_RESERVE_FACTOR = 0.12e18;

    constructor() {
        _setProposalDescription(
            abi.encodePacked("Smoke test: bump Base USDC reserve factor")
        );
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MOONWELL_USDC", BASE_CHAIN_ID),
            abi.encodeWithSignature(
                "_setReserveFactor(uint256)",
                NEW_RESERVE_FACTOR
            ),
            "Bump Base USDC reserve factor to 12%",
            ActionType.Base
        );
    }

    function teardown(Addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);
        assertEq(
            MToken(addresses.getAddress("MOONWELL_USDC"))
                .reserveFactorMantissa(),
            NEW_RESERVE_FACTOR,
            "Base USDC reserve factor not updated"
        );
    }
}

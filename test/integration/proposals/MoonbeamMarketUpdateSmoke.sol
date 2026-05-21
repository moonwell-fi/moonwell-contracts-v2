//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Comptroller} from "@protocol/Comptroller.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_FORK_ID, MOONBEAM_FORK_ID, MOONBEAM_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title MoonbeamMarketUpdateSmoke
/// @notice Cross-chain smoke proposal used by MigrationHarness.testPhaseF2 to
///         prove the new Ethereum MultichainGovernorV2 can hop through
///         Wormhole to the Moonbeam TemporalGovernor and mutate a live
///         Moonbeam Comptroller parameter. Bumps Moonbeam Unitroller's
///         closeFactorMantissa.
///
///         Targets the Unitroller (Moonbeam Comptroller proxy) rather than a
///         specific mToken because the Unitroller's admin is guaranteed to be
///         TemporalGovernor after MIP-X58 + MIP-E01 (asserted in
///         mip-e01.validate). Some Moonbeam mTokens may have non-governor
///         admins on mainnet and would be skipped by x58's pendingAdmin
///         sweep — targeting Unitroller avoids that ambiguity.
contract MoonbeamMarketUpdateSmoke is HybridProposalV2 {
    string public constant override name = "MOONBEAM-MARKET-UPDATE-SMOKE";

    /// @notice 55% close factor — distinct from Eth (15%) and Base (12%)
    ///         reserve-factor smoke values so the three smokes are visually
    ///         disambiguable. mip-e00's deployed default for closeFactor is
    ///         0.5e18; bumping to 0.55e18 is a small operational tweak.
    uint256 public constant NEW_CLOSE_FACTOR = 0.55e18;

    constructor() {
        _setProposalDescription(
            abi.encodePacked("Smoke test: bump Moonbeam closeFactor")
        );
        // Distinct Wormhole nonce so this proposal's publishMessage doesn't
        // collide with mip-e00's or mip-e01's.
        nonce = 4;
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function teardown(Addresses, address) public pure override {}

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("UNITROLLER", MOONBEAM_CHAIN_ID),
            abi.encodeWithSignature(
                "_setCloseFactor(uint256)",
                NEW_CLOSE_FACTOR
            ),
            "Bump Moonbeam closeFactor to 55%",
            ActionType.Moonbeam
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);
        Comptroller mc = Comptroller(addresses.getAddress("UNITROLLER"));
        assertEq(
            mc.closeFactorMantissa(),
            NEW_CLOSE_FACTOR,
            "Moonbeam closeFactor not updated"
        );
    }
}

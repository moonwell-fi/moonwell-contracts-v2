//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {MToken} from "@protocol/MToken.sol";
import {Unitroller} from "@protocol/Unitroller.sol";
import {Comptroller} from "@protocol/Comptroller.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {VotingPowerAggregator} from "@protocol/governance/multichain/VotingPowerAggregator.sol";

import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {ChainIds, ETHEREUM_FORK_ID, MOONBEAM_FORK_ID, ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID} from "@utils/ChainIds.sol";

/// @title MIP-E01: First Ethereum Proposal — Complete cross-chain ownership transfers
/// @author Moonwell Contributors
/// @notice First proposal submitted to MultichainGovernorV2. Completes the
///         Ownable2Step and pendingAdmin transfers that MIP-X56 +
///         PostDeployEthereumXWell + MIP-E00 leave in a half-transferred
///         state. Specifically:
///
///         ETHEREUM (executed directly by MultichainGovernorV2):
///         1. xWELL.acceptOwnership() — PostDeployEthereumXWell.s.sol set
///            pendingOwner; no proposal accepts.
///         2. VotingPowerAggregator.acceptOwnership() — MIP-X56 afterDeploy
///            set pendingOwner; no proposal accepts.
///
///         MOONBEAM (executed by TemporalGovernor via Wormhole):
///         3. Unitroller._acceptAdmin() — MIP-X56 set pendingAdmin = TG.
///         4. For every Moonbeam mToken with pendingAdmin == TG:
///            mToken._acceptAdmin() — MIP-X56 set pendingAdmin.
///
///         xWELL bridging activation (addTrustedSenders on the four bridge
///         adapters) is handled by a separate in-flight Moonbeam-governor
///         proposal and is intentionally NOT part of this proposal.
contract mipe01 is HybridProposalV2 {
    using ChainIds for uint256;

    string public constant override name = "MIP-E01";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-e01/MIP-E01.md")
        );
        _setProposalDescription(proposalDescription);
        nonce = 3;
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    function deploy(Addresses, address) public override {}

    function afterDeploy(Addresses, address) public override {}

    function teardown(Addresses, address) public pure override {}

    function build(Addresses addresses) public override {
        // ------ Ethereum-side accepts ------

        _pushAction(
            addresses.getAddress("xWELL_PROXY", ETHEREUM_CHAIN_ID),
            abi.encodeWithSignature("acceptOwnership()"),
            "MultichainGovernorV2 accepts ownership of xWELL on Ethereum",
            ActionType.Ethereum
        );

        _pushAction(
            addresses.getAddress("VOTING_POWER_AGGREGATOR", ETHEREUM_CHAIN_ID),
            abi.encodeWithSignature("acceptOwnership()"),
            "MultichainGovernorV2 accepts ownership of VotingPowerAggregator on Ethereum",
            ActionType.Ethereum
        );

        // ------ Moonbeam-side accepts (via Wormhole → TemporalGovernor) ------
        //
        // Enumerate Moonbeam mTokens via Comptroller.getAllMarkets() at
        // build time and push _acceptAdmin only for the ones whose
        // pendingAdmin is the TemporalGovernor (i.e. those MIP-X56 set
        // pendingAdmin on). Querying live state means we automatically
        // pick up whatever the on-chain reality is — markets added after
        // MIP-X56 won't be in the list, and markets whose admin wasn't
        // the old MultichainGovernor are skipped.
        uint256 currentForkBefore = vm.activeFork();
        vm.selectFork(MOONBEAM_FORK_ID);

        address moonbeamTG = addresses.getAddress("TEMPORAL_GOVERNOR");
        address moonbeamUnitroller = addresses.getAddress("UNITROLLER");

        // Unitroller _acceptAdmin (push only if pendingAdmin == TG).
        if (_pendingAdminIs(moonbeamUnitroller, moonbeamTG)) {
            _pushAction(
                moonbeamUnitroller,
                abi.encodeWithSignature("_acceptAdmin()"),
                "TemporalGovernor accepts admin on Moonbeam Unitroller",
                ActionType.Moonbeam
            );
        }

        // Per-mToken _acceptAdmin.
        Comptroller mc = Comptroller(moonbeamUnitroller);
        MToken[] memory markets = mc.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address mtoken = address(markets[i]);
            if (!_pendingAdminIs(mtoken, moonbeamTG)) continue;
            _pushAction(
                mtoken,
                abi.encodeWithSignature("_acceptAdmin()"),
                _moonbeamAcceptAdminDescription(mtoken),
                ActionType.Moonbeam
            );
        }

        vm.selectFork(currentForkBefore);
    }

    function validate(Addresses addresses, address) public override {
        address governor = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_V2_PROXY",
            ETHEREUM_CHAIN_ID
        );

        // Ethereum-side
        vm.selectFork(ETHEREUM_FORK_ID);
        assertEq(
            xWELL(addresses.getAddress("xWELL_PROXY")).owner(),
            governor,
            "Eth xWELL owner not MultichainGovernorV2 post-E01"
        );
        assertEq(
            VotingPowerAggregator(
                addresses.getAddress("VOTING_POWER_AGGREGATOR")
            ).owner(),
            governor,
            "Eth VotingPowerAggregator owner not MultichainGovernorV2 post-E01"
        );

        // Moonbeam-side
        vm.selectFork(MOONBEAM_FORK_ID);
        address moonbeamTG = addresses.getAddress("TEMPORAL_GOVERNOR");
        Unitroller moonbeamUnitroller = Unitroller(
            addresses.getAddress("UNITROLLER")
        );
        assertEq(
            moonbeamUnitroller.admin(),
            moonbeamTG,
            "Moonbeam Unitroller admin not TemporalGovernor post-E01"
        );

        Comptroller mc = Comptroller(address(moonbeamUnitroller));
        MToken[] memory markets = mc.getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            address mtoken = address(markets[i]);
            // Skip mTokens whose admin was never the old MultichainGovernor —
            // they were not part of MIP-X56's pendingAdmin sweep, so MIP-E01
            // didn't push an _acceptAdmin for them and their admin is
            // unrelated to TG.
            if (!_wasInPendingSweep(mtoken, moonbeamTG)) continue;
            assertEq(
                MToken(mtoken).admin(),
                moonbeamTG,
                "Moonbeam mToken admin not TemporalGovernor post-E01"
            );
        }
    }

    /// @notice Returns true if `target.pendingAdmin() == expected`.
    function _pendingAdminIs(
        address target,
        address expected
    ) internal view returns (bool) {
        (bool ok, bytes memory data) = target.staticcall(
            abi.encodeWithSignature("pendingAdmin()")
        );
        if (!ok || data.length < 32) return false;
        return abi.decode(data, (address)) == expected;
    }

    /// @notice Heuristic used in validate(): we know an mToken was part of
    /// MIP-X56's pendingAdmin sweep iff its current admin is the TG (it
    /// accepted in this proposal) OR its pendingAdmin is still the TG
    /// (this proposal hadn't yet been executed when validate ran in a
    /// dry-run scenario). Anything else (e.g. a multisig admin that was
    /// never the old MultichainGovernor) is skipped.
    function _wasInPendingSweep(
        address mtoken,
        address tg
    ) internal view returns (bool) {
        (bool ok, bytes memory data) = mtoken.staticcall(
            abi.encodeWithSignature("admin()")
        );
        if (!ok || data.length < 32) return false;
        if (abi.decode(data, (address)) == tg) return true;
        return _pendingAdminIs(mtoken, tg);
    }

    function _moonbeamAcceptAdminDescription(
        address mtoken
    ) internal pure returns (string memory) {
        return
            string(
                abi.encodePacked(
                    "TemporalGovernor accepts admin on Moonbeam mToken ",
                    _addrToString(mtoken)
                )
            );
    }

    function _addrToString(address addr) internal pure returns (string memory) {
        bytes memory s = new bytes(42);
        s[0] = "0";
        s[1] = "x";
        bytes16 alphabet = "0123456789abcdef";
        for (uint256 i = 0; i < 20; i++) {
            uint8 b = uint8(uint160(addr) >> (8 * (19 - i)));
            s[2 + 2 * i] = alphabet[b >> 4];
            s[3 + 2 * i] = alphabet[b & 0x0f];
        }
        return string(s);
    }
}

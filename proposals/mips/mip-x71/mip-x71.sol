//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ActionType} from "@proposals/proposalTypes/IProposal.sol";
import {MarketUpdateV2Template} from "@proposals/templates/MarketUpdateV2.sol";
import {BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {IMetaMorpho, IMetaMorphoStaticTyping} from "@protocol/morpho/IMetaMorpho.sol";

interface IPauseGuardianHolder {
    function pauseGuardian() external view returns (address);

    function admin() external view returns (address);
}

/// @title MIP-X71: Anthias risk parameters + pause guardian migration
/// @notice market updates come from x71.json via the template; this adds the
/// Comptroller + MRD pause guardian move to F-ETH-SEC on Base and OP Mainnet,
/// and submits F-ETH-SEC as guardian of the Moonwell MetaMorpho vaults there.
/// Ethereum already uses F-ETH-SEC; Moonbeam is halted and has no such Safe.
/// forge script proposals/mips/mip-x71/mip-x71.sol:mipx71 --ffi -vvv
contract mipx71 is MarketUpdateV2Template {
    string public constant NEW_PAUSE_GUARDIAN_KEY = "F-ETH-SEC";
    string public constant OLD_PAUSE_GUARDIAN_KEY = "PAUSE_GUARDIAN_DEPRECATED";

    function name() external pure override returns (string memory) {
        return "MIP-X71";
    }

    /// @notice pre-state asserts live here, not in build(), so a harness that
    /// builds twice on one fork does not trip them
    function afterDeploy(Addresses addresses, address) public override {
        _checkPreState(addresses, BASE_FORK_ID);
        _checkPreState(addresses, OPTIMISM_FORK_ID);

        vm.selectFork(primaryForkId());
    }

    /// @notice MetaMorpho vaults whose guardian is the deprecated multisig
    function vaults(uint256 forkId) public pure returns (string[] memory v) {
        if (forkId == BASE_FORK_ID) {
            v = new string[](4);
            v[0] = "cbBTC_METAMORPHO_VAULT";
            v[1] = "WETH_METAMORPHO_VAULT";
            v[2] = "USDC_METAMORPHO_VAULT";
            v[3] = "EURC_METAMORPHO_VAULT";
        } else if (forkId == OPTIMISM_FORK_ID) {
            v = new string[](1);
            v[0] = "USDC_METAMORPHO_VAULT";
        }
    }

    function build(Addresses addresses) public override {
        super.build(addresses);

        _buildPauseGuardian(addresses, BASE_FORK_ID, ActionType.Base);
        _buildPauseGuardian(addresses, OPTIMISM_FORK_ID, ActionType.Optimism);

        vm.selectFork(primaryForkId());
    }

    function validate(Addresses addresses, address caller) public override {
        super.validate(addresses, caller);

        _validatePauseGuardian(addresses, BASE_FORK_ID);
        _validatePauseGuardian(addresses, OPTIMISM_FORK_ID);

        _validateVaultGuardian(addresses, BASE_FORK_ID);
        _validateVaultGuardian(addresses, OPTIMISM_FORK_ID);

        vm.selectFork(primaryForkId());
    }

    function _checkPreState(Addresses addresses, uint256 forkId) internal {
        vm.selectFork(forkId);

        address unitroller = addresses.getAddress("UNITROLLER");
        address oldGuardian = addresses.getAddress(OLD_PAUSE_GUARDIAN_KEY);

        // both setters are gated on the Comptroller admin (MRD reads it too)
        assertEq(
            IPauseGuardianHolder(unitroller).admin(),
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            "MIP-X71: Comptroller admin is not the Temporal Governor"
        );
        assertEq(
            IPauseGuardianHolder(unitroller).pauseGuardian(),
            oldGuardian,
            "MIP-X71: Comptroller pause guardian drifted"
        );
        assertEq(
            IPauseGuardianHolder(addresses.getAddress("MRD_PROXY"))
                .pauseGuardian(),
            oldGuardian,
            "MIP-X71: MRD pause guardian drifted"
        );

        string[] memory v = vaults(forkId);
        for (uint256 i = 0; i < v.length; i++) {
            address vault = addresses.getAddress(v[i]);
            (, uint64 validAt) = IMetaMorphoStaticTyping(vault)
                .pendingGuardian();

            assertEq(
                IMetaMorpho(vault).owner(),
                addresses.getAddress("TEMPORAL_GOVERNOR"),
                "MIP-X71: vault owner is not the Temporal Governor"
            );
            assertEq(
                IMetaMorpho(vault).guardian(),
                oldGuardian,
                "MIP-X71: vault guardian drifted"
            );
            // submitGuardian reverts AlreadyPending otherwise
            assertEq(validAt, 0, "MIP-X71: vault guardian already pending");
        }
    }

    function _buildPauseGuardian(
        Addresses addresses,
        uint256 forkId,
        ActionType actionType
    ) internal {
        vm.selectFork(forkId);

        address newGuardian = addresses.getAddress(NEW_PAUSE_GUARDIAN_KEY);

        _pushAction(
            addresses.getAddress("UNITROLLER"),
            abi.encodeWithSignature("_setPauseGuardian(address)", newGuardian),
            "Set the Comptroller pause guardian to F-ETH-SEC",
            actionType
        );
        _pushAction(
            addresses.getAddress("MRD_PROXY"),
            abi.encodeWithSignature("_setPauseGuardian(address)", newGuardian),
            "Set the MultiRewardDistributor pause guardian to F-ETH-SEC",
            actionType
        );

        string[] memory v = vaults(forkId);
        for (uint256 i = 0; i < v.length; i++) {
            _pushAction(
                addresses.getAddress(v[i]),
                abi.encodeWithSignature("submitGuardian(address)", newGuardian),
                string.concat("Submit F-ETH-SEC as guardian of ", v[i]),
                actionType
            );
        }
    }

    /// @notice Comptroller._setPauseGuardian returns an error code instead of
    /// reverting, so only the resulting storage proves the action landed
    function _validatePauseGuardian(
        Addresses addresses,
        uint256 forkId
    ) internal {
        vm.selectFork(forkId);

        address newGuardian = addresses.getAddress(NEW_PAUSE_GUARDIAN_KEY);

        assertEq(
            IPauseGuardianHolder(addresses.getAddress("UNITROLLER"))
                .pauseGuardian(),
            newGuardian,
            "MIP-X71: Comptroller pause guardian not updated"
        );
        assertEq(
            IPauseGuardianHolder(addresses.getAddress("MRD_PROXY"))
                .pauseGuardian(),
            newGuardian,
            "MIP-X71: MRD pause guardian not updated"
        );
    }

    /// @notice submitGuardian only queues the change behind the vault
    /// timelock; prove the queued value and that acceptGuardian lands after it
    function _validateVaultGuardian(
        Addresses addresses,
        uint256 forkId
    ) internal {
        vm.selectFork(forkId);

        address newGuardian = addresses.getAddress(NEW_PAUSE_GUARDIAN_KEY);
        string[] memory v = vaults(forkId);

        for (uint256 i = 0; i < v.length; i++) {
            address vault = addresses.getAddress(v[i]);
            (address pending, uint64 validAt) = IMetaMorphoStaticTyping(vault)
                .pendingGuardian();

            assertEq(
                pending,
                newGuardian,
                "MIP-X71: vault guardian not pending"
            );
            // PostProposalCheck may warp after execution, so bound, not equate
            assertLe(
                validAt,
                vm.getBlockTimestamp() + IMetaMorpho(vault).timelock(),
                "MIP-X71: vault guardian validAt past execution + timelock"
            );
            assertGt(validAt, 0, "MIP-X71: vault guardian validAt unset");

            uint256 snapshot = vm.snapshot();
            if (vm.getBlockTimestamp() < validAt) vm.warp(validAt);
            IMetaMorpho(vault).acceptGuardian();
            assertEq(
                IMetaMorpho(vault).guardian(),
                newGuardian,
                "MIP-X71: vault guardian not accepted after timelock"
            );
            vm.revertTo(snapshot);
        }
    }
}

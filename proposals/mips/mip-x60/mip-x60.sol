//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";

import {RewardsDistributionV2Template} from "@proposals/templates/RewardsDistributionV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

interface IAdminTwoStep {
    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);
}

interface IComptrollerMarkets {
    function getAllMarkets() external view returns (address[] memory);
}

/// @title MIP-X60
/// @notice Rewards distribution for the 2026-06-15 -> 2026-07-15 epoch.
///         First rewards MIP executed from Ethereum (MultichainGovernorV2):
///         - chain 1 is the source chain: FOUNDATION_MULTISIG funds the
///           governor (xWELL bridged to the Base Temporal Governor via the
///           WormholeBridgeAdapter on-chain-quoted path) and funds the
///           Ethereum MRD directly via transferFrom
///         - Base/Optimism remain external destination chains
///         - Moonbeam is a pure destination chain in wind-down mode
///         The template's beforeSimulationHook already simulates the
///         foundation's xWELL approval (and sim-only balance top-up), so no
///         extra hook is needed here.
///
///         This MIP also completes the MIP-X58 Moonbeam admin migration:
///         X58 called _setPendingAdmin(TEMPORAL_GOVERNOR) on the Unitroller
///         and every mToken, but the two-step handoff was never finished, so
///         admin is still the old MultichainGovernor and the comptroller
///         rejects _setRewardSpeed from the Temporal Governor. Before the
///         template's Moonbeam actions, this proposal pushes _acceptAdmin()
///         (executed by the Temporal Governor, which is the pendingAdmin) on
///         the Unitroller and on every market whose handoff is still pending.
contract mipx60 is RewardsDistributionV2Template {
    using ChainIds for uint256;

    function name() external pure override returns (string memory) {
        return "MIP-X60";
    }

    function build(Addresses addresses) public override {
        // Accept actions must precede the template's Moonbeam reward-speed
        // actions inside the Moonbeam VAA bundle (actions execute in push order).
        _buildAcceptMoonbeamAdmin(addresses);

        super.build(addresses);
    }

    function _buildAcceptMoonbeamAdmin(Addresses addresses) internal {
        vm.selectFork(MOONBEAM_FORK_ID);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address unitroller = addresses.getAddress("UNITROLLER");

        if (
            IAdminTwoStep(unitroller).pendingAdmin() == temporalGovernor &&
            IAdminTwoStep(unitroller).admin() != temporalGovernor
        ) {
            _pushAction(
                unitroller,
                abi.encodeWithSignature("_acceptAdmin()"),
                "Accept the X58 admin handoff on the Unitroller (old MultichainGovernor -> Temporal Governor)"
            );
        }

        address[] memory markets = IComptrollerMarkets(unitroller)
            .getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            // Tolerate markets without the two-step admin surface
            try IAdminTwoStep(markets[i]).pendingAdmin() returns (
                address pending
            ) {
                if (
                    pending == temporalGovernor &&
                    IAdminTwoStep(markets[i]).admin() != temporalGovernor
                ) {
                    _pushAction(
                        markets[i],
                        abi.encodeWithSignature("_acceptAdmin()"),
                        string.concat(
                            "Accept the X58 admin handoff on market ",
                            vm.toString(markets[i])
                        )
                    );
                }
            } catch {}
        }
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        // The X58 handoff must be complete after execution
        vm.selectFork(MOONBEAM_FORK_ID);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address unitroller = addresses.getAddress("UNITROLLER");

        assertEq(
            IAdminTwoStep(unitroller).admin(),
            temporalGovernor,
            "Unitroller admin must be the Temporal Governor after X60"
        );

        address[] memory markets = IComptrollerMarkets(unitroller)
            .getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            try IAdminTwoStep(markets[i]).admin() returns (address admin) {
                assertEq(
                    admin,
                    temporalGovernor,
                    string.concat(
                        "market admin must be the Temporal Governor: ",
                        vm.toString(markets[i])
                    )
                );
            } catch {}
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";

import {Comptroller} from "@protocol/Comptroller.sol";
import {PostProposalCheck} from "@test/integration/PostProposalCheck.sol";

/// @notice Proves chains/<id>.json memorializes every privileged Comptroller
/// role once the pending proposals have run. A proposal that rotates a role
/// must update the registry in the same PR (MOO-586).
contract PrivilegedRoleRegistryIntegrationTest is PostProposalCheck {
    using ChainIds for uint256;

    function testComptrollerRolesMatchRegistry() public {
        uint256 chains;
        for (uint256 f = BASE_FORK_ID; f <= ETHEREUM_FORK_ID; f++) {
            vm.selectFork(f);
            if (
                !addresses.isAddressSet("UNITROLLER") ||
                addresses.getAddress("UNITROLLER").code.length == 0
            ) continue;
            chains++;

            Comptroller comptroller = Comptroller(
                addresses.getAddress("UNITROLLER")
            );
            string memory chain = vm.toString(block.chainid);

            assertEq(
                comptroller.admin(),
                _registered(
                    "TEMPORAL_GOVERNOR",
                    "MULTICHAIN_GOVERNOR_V2_PROXY"
                ),
                string.concat(
                    "Comptroller admin not in registry, chain ",
                    chain
                )
            );
            assertEq(
                comptroller.pauseGuardian(),
                addresses.getAddress("PAUSE_GUARDIAN"),
                string.concat("PAUSE_GUARDIAN stale, chain ", chain)
            );

            address capGuardian = _registered(
                "BORROW_SUPPLY_GUARDIAN",
                "CAP_GUARDIAN"
            );
            assertEq(
                comptroller.borrowCapGuardian(),
                capGuardian,
                string.concat("borrow cap guardian stale, chain ", chain)
            );
            assertEq(
                comptroller.supplyCapGuardian(),
                capGuardian,
                string.concat("supply cap guardian stale, chain ", chain)
            );
        }
        assertGt(chains, 0, "no chain checked");
    }

    /// @notice the first registry key set on the active chain
    function _registered(
        string memory primary,
        string memory fallbackKey
    ) internal view returns (address) {
        if (addresses.isAddressSet(primary)) {
            return addresses.getAddress(primary);
        }
        return addresses.getAddress(fallbackKey);
    }
}

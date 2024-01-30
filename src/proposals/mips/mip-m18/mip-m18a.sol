//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to create the Multichain Governor contract
contract mipm18a is HybridProposal, MultichainGovernorDeploy {
    /// @notice deployment name
    string public constant name = "MIP-M18A";

    /// @notice slot for the Proxy Admin
    bytes32 _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice slot for the implementation address
    bytes32 _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function deploy(Addresses addresses, address) public override {
        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");
        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY", governorProxy);
        addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl);
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {}

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
    }

    function validate(Addresses addresses, address) public override {
        {
            bytes32 data = vm.load(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                _ADMIN_SLOT
            );

            assertEq(
                bytes32(
                    uint256(uint160(addresses.getAddress("MRD_PROXY_ADMIN")))
                ),
                data,
                "mrd proxy admin not set correctly"
            );
        }

        {
            bytes32 data = vm.load(
                addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
                _IMPLEMENTATION_SLOT
            );

            assertEq(
                bytes32(
                    uint256(
                        uint160(
                            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL")
                        )
                    )
                ),
                data,
                "mrd implementation not set correctly"
            );
        }
    }
}

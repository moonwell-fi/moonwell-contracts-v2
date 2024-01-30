//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {ChainIds} from "@test/utils/ChainIds.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/Governance/MultichainGovernor/MultichainGovernorDeploy.sol";

/// Proposal to run on Moonbeam to create the Multichain Governor contract
contract mipm18a is ChainIds, HybridProposal, MultichainGovernorDeploy {
    /// @notice deployment name
    string public constant name = "MIP-M18A";

    /// @notice slot for the Proxy Admin
    bytes32 _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice slot for the implementation address
    bytes32 _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice proposal's actions all happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses addresses, address) public override {
        address proxyAdmin = addresses.getAddress(
            "MOONBEAM_PROXY_ADMIN",
            moonBeamChainId
        );

        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress(
            "MULTICHAIN_GOVERNOR_PROXY",
            governorProxy,
            moonBeamChainId
        );
        addresses.addAddress(
            "MULTICHAIN_GOVERNOR_IMPL",
            governorImpl,
            moonBeamChainId
        );
    }

    function afterDeploy(Addresses, address) public override {}

    function afterDeploySetup(Addresses) public override {}

    function build(Addresses) public override {}

    function teardown(Addresses, address) public pure override {}

    /// nothing to run
    function run(Addresses, address) public override {}

    function validate(Addresses addresses, address) public override {
        {
            bytes32 data = vm.load(
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    moonBeamChainId
                ),
                _ADMIN_SLOT
            );

            assertEq(
                bytes32(
                    uint256(
                        uint160(
                            addresses.getAddress(
                                "MOONBEAM_PROXY_ADMIN",
                                moonBeamChainId
                            )
                        )
                    )
                ),
                data,
                "mrd proxy admin not set correctly"
            );
        }

        {
            bytes32 data = vm.load(
                addresses.getAddress(
                    "MULTICHAIN_GOVERNOR_PROXY",
                    moonBeamChainId
                ),
                _IMPLEMENTATION_SLOT
            );

            assertEq(
                bytes32(
                    uint256(
                        uint160(
                            addresses.getAddress(
                                "MULTICHAIN_GOVERNOR_IMPL",
                                moonBeamChainId
                            )
                        )
                    )
                ),
                data,
                "mrd implementation not set correctly"
            );
        }
    }
}

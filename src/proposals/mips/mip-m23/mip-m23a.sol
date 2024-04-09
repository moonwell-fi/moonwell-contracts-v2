//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MultichainGovernorDeploy} from "@protocol/governance/multichain/MultichainGovernorDeploy.sol";

import {validateProxy} from "@proposals/utils/ProxyUtils.sol";

/// Proposal to run on Moonbeam to create the Multichain Governor contract
/// to simulate: DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script
/// src/proposals/mips/mip-m23/mip-m23a.sol:mipm23a --fork-url moonbeam
/// to execute: DO_DEPLOY=true DO_VALIDATE=true DO_PRINT=true forge script \
/// src/proposals/mips/mip-m23/mip-m23a.sol:mipm23a
/// --broadcast --slow --fork-url moonbeam
/// Once the proposal is execute, MULTICHAIN_GOVERNOR_PROXY and
/// MULTICHAIN_GOVERNOR_IMPL must be added to the addresses.json file
/// before the next proposal can be executed.
contract mipm23a is HybridProposal, MultichainGovernorDeploy {
    /// @notice deployment name
    string public constant name = "MIP-M23A";

    /// @notice proposal's actions all happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses addresses, address) public override {
        if (
            addresses.isAddressSet("MULTICHAIN_GOVERNOR_PROXY", block.chainid)
        ) {
            return;
        }

        address proxyAdmin = addresses.getAddress("MOONBEAM_PROXY_ADMIN");

        (
            address governorProxy,
            address governorImpl
        ) = deployMultichainGovernor(proxyAdmin);

        addresses.addAddress("MULTICHAIN_GOVERNOR_PROXY", governorProxy, true);
        addresses.addAddress("MULTICHAIN_GOVERNOR_IMPL", governorImpl, true);
    }

    function validate(Addresses addresses, address) public view override {
        validateProxy(
            vm,
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            addresses.getAddress("MULTICHAIN_GOVERNOR_IMPL"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "moonbeam proxies for multichain governor"
        );
    }
}

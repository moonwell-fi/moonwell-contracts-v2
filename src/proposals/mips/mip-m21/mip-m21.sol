//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";

contract mipm21 is GovernanceProposal {
    string public constant name = "MIP-M19";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m21/MIP-M21.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("WORMHOLE_UNWRAPPER_ADAPTER")) {
            WormholeUnwrapperAdapter wormholeUnwrapperAdapter = new WormholeUnwrapperAdapter();

            addresses.addAddress(
                "WORMHOLE_UNWRAPPER_ADAPTER",
                address(wormholeUnwrapperAdapter),
                true
            );
        }
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        /// @dev Upgrade wormhole bridge adapter to wormhole unwrapper adapter
        _pushGovernanceAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Upgrade wormhole bridge adapter to wormhole unwrapper adapter",
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER")
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            "Set lockbox on wormhole unwrapper adapter",
            abi.encodeWithSignature(
                "setLockbox(address)",
                addresses.getAddress("xWELL_LOCKBOX")
            )
        );
    }

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
        setDebug(true);

        _simulateGovernanceActions(
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            address(this)
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function validate(Addresses addresses, address) public override {
        validateProxy(
            vm,
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            addresses.getAddress("WORMHOLE_UNWRAPPER_ADAPTER"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Moonbeam proxies for wormhole bridge adapter"
        );

        assertEq(
            WormholeUnwrapperAdapter(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).lockbox(),
            addresses.getAddress("xWELL_LOCKBOX"),
            "lockbox not correctly set"
        );
    }
}

//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {TemporalGovernor} from "@protocol/Governance/TemporalGovernor.sol";
import "@forge-std/Test.sol";
import {Addresses} from "@proposals/Addresses.sol";

import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {ITemporalGovernor} from "@protocol/Governance/ITemporalGovernor.sol";
import {MultichainGovernor} from "@protocol/Governance/MultichainGovernor/MultichainGovernor.sol";
import {WormholeUnwrapperAdapter} from "@protocol/xWELL/WormholeUnwrapperAdapter.sol";

contract Proposal8 is HybridProposal {
    string public constant name = "PROPOSAL_8";

    constructor() {
        _setProposalDescription(
            bytes("Upgrade bridge adapter to use unwrapper")
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    function deploy(Addresses addresses, address) public override {
        WormholeUnwrapperAdapter wormholeUnwrapperAdapter = new WormholeUnwrapperAdapter();

        addresses.changeAddress(
            "WORMHOLE_BRIDGE_ADAPTER_LOGIC",
            address(wormholeUnwrapperAdapter),
            true
        );
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "upgradeTo(address)",
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC")
            ),
            "Upgrade Wormhole Bridge Adapter",
            true
        );

        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature(
                "setLockbox(address)",
                addresses.getAddress("xWELL_LOCKBOX")
            ),
            "Set Lockbox",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        _runMoonbeamMultichainGovernor(addresses, address(1000000));
    }

    function validate(Addresses addresses, address) public override {
        assertEq(
            (
                WormholeUnwrapperAdapter(
                    addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
                )
            ).lockbox(),
            addresses.getAddress("xWELL_LOCKBOX")
        );

        validateProxy(
            vm,
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_LOGIC"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Wormhole Bridge Adapter orrect proxy"
        );
    }
}

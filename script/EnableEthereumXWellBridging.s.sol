// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/*
 Ethereum-side counterpart of MIP-X55.

 Runs on Ethereum mainnet as MOONWELL_DEPLOYER (current owner of xWELL_PROXY
 and WORMHOLE_BRIDGE_ADAPTER_PROXY). In one broadcast it:

   1. Wires the Ethereum WormholeBridgeAdapter to recognize Moonbeam / Base /
      Optimism peers (addTrustedSenders + setTargetAddresses).
   2. Transfers ownership of WormholeBridgeAdapter + xWELL to
      FOUNDATION_MULTISIG.

 The multisig must complete the handover by submitting two Safe transactions
 calling `acceptOwnership()` on each proxy (Ownable2Step).

 to simulate (no broadcast):
     forge script script/EnableEthereumXWellBridging.s.sol:EnableEthereumXWellBridging \
       --rpc-url ethereum -vvvv

 to run:
    forge script script/EnableEthereumXWellBridging.s.sol:EnableEthereumXWellBridging \
       --rpc-url ethereum -vvvv --broadcast \
       --private-key $DEPLOYER_PRIVATE_KEY
*/
contract EnableEthereumXWellBridging is Script {
    function run() public {
        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "EnableEthereumXWellBridging: must run on Ethereum mainnet"
        );

        Addresses addresses = new Addresses();

        address deployer = addresses.getAddress("MOONWELL_DEPLOYER");
        address multisig = addresses.getAddress("FOUNDATION_MULTISIG");

        xWELL xwell = xWELL(addresses.getAddress("xWELL_PROXY"));
        WormholeBridgeAdapter adapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        require(
            xwell.owner() == deployer,
            "xWELL_PROXY not owned by MOONWELL_DEPLOYER"
        );
        require(
            adapter.owner() == deployer,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY not owned by MOONWELL_DEPLOYER"
        );

        WormholeTrustedSender.TrustedSender[] memory peers = _buildPeers(
            addresses
        );

        vm.startBroadcast(deployer);

        // 1. Allow inbound VAAs from Moonbeam / Base / Optimism.
        adapter.addTrustedSenders(peers);

        // 2. Route outbound bridge() calls to the same peers on each chain.
        adapter.setTargetAddresses(peers);

        // 3. Hand off ownership to the multisig (Ownable2Step → multisig must
        //    later call acceptOwnership on both proxies).
        adapter.transferOwnership(multisig);
        xwell.transferOwnership(multisig);

        vm.stopBroadcast();

        _validate(adapter, xwell, peers, multisig);

        console.log(
            "Ethereum WormholeBridgeAdapter wired to Moonbeam/Base/Optimism"
        );
        console.log(
            "xWELL_PROXY pendingOwner:                  ",
            xwell.pendingOwner()
        );
        console.log(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pendingOwner:",
            adapter.pendingOwner()
        );
        console.log(
            "Next step: FOUNDATION_MULTISIG must call acceptOwnership() on both proxies."
        );
    }

    function _buildPeers(
        Addresses addresses
    )
        internal
        view
        returns (WormholeTrustedSender.TrustedSender[] memory peers)
    {
        peers = new WormholeTrustedSender.TrustedSender[](3);
        peers[0] = WormholeTrustedSender.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                MOONBEAM_CHAIN_ID
            )
        });
        peers[1] = WormholeTrustedSender.TrustedSender({
            chainId: BASE_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                BASE_CHAIN_ID
            )
        });
        peers[2] = WormholeTrustedSender.TrustedSender({
            chainId: OPTIMISM_WORMHOLE_CHAIN_ID,
            addr: addresses.getAddress(
                "WORMHOLE_BRIDGE_ADAPTER_PROXY",
                OPTIMISM_CHAIN_ID
            )
        });
    }

    function _validate(
        WormholeBridgeAdapter adapter,
        xWELL xwell,
        WormholeTrustedSender.TrustedSender[] memory peers,
        address multisig
    ) internal view {
        for (uint256 i = 0; i < peers.length; i++) {
            require(
                adapter.isTrustedSender(peers[i].chainId, peers[i].addr),
                "Adapter: peer missing from trustedSenders"
            );
            require(
                adapter.targetAddress(peers[i].chainId) == peers[i].addr,
                "Adapter: peer missing from targetAddress map"
            );
        }
        require(
            adapter.pendingOwner() == multisig,
            "Adapter: pendingOwner not multisig"
        );
        require(
            xwell.pendingOwner() == multisig,
            "xWELL: pendingOwner not multisig"
        );
    }
}

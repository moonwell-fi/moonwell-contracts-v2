// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {MintLimits} from "@protocol/xWELL/MintLimits.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeTrustedSender} from "@protocol/governance/WormholeTrustedSender.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_CHAIN_ID, MOONBEAM_CHAIN_ID, BASE_CHAIN_ID, OPTIMISM_CHAIN_ID, MOONBEAM_WORMHOLE_CHAIN_ID, BASE_WORMHOLE_CHAIN_ID, OPTIMISM_WORMHOLE_CHAIN_ID} from "@utils/ChainIds.sol";

/*
 Ethereum-side counterpart of MIP-X55.

 Runs on Ethereum mainnet as MOONWELL_DEPLOYER (current owner of xWELL_PROXY
 and WORMHOLE_BRIDGE_ADAPTER_PROXY). In one broadcast it:

   1. Ensures the Ethereum WormholeBridgeAdapter is a registered minter/burner
      on xWELL with the canonical bufferCap + rateLimitPerSecond.
   2. Wires the Ethereum WormholeBridgeAdapter to recognize Moonbeam / Base /
      Optimism peers (addTrustedSenders + setTargetAddresses), skipping any
      peer already configured so the script is idempotent.
   3. Transfers ownership of WormholeBridgeAdapter + xWELL to
      PAUSE_GUARDIAN.

 The pauseGuardian completes the handover by submitting two Safe transactions
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
    /// @notice Canonical Ethereum xWELL bridge rate-limit params
    ///         (mirrors `DeployXWellEthereum.s.sol` and `mip-x45.sol`).
    uint112 public constant ETH_XWELL_BUFFER_CAP = 100_000_000 * 1e18;
    uint128 public constant ETH_XWELL_RATE_LIMIT_PER_SECOND = 1158 * 1e18; // ~19m/day

    function run() public {
        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "EnableEthereumXWellBridging: must run on Ethereum mainnet"
        );

        Addresses addresses = new Addresses();

        address deployer = addresses.getAddress("MOONWELL_DEPLOYER");
        address pauseGuardian = addresses.getAddress("PAUSE_GUARDIAN");

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

        WormholeTrustedSender.TrustedSender[] memory allPeers = _buildPeers(
            addresses
        );

        // Compute the subset of peers that aren't already wired so re-runs
        // don't revert in EnumerableSet.add.
        WormholeTrustedSender.TrustedSender[]
            memory peersToAddSender = _filterMissingSenders(adapter, allPeers);
        WormholeTrustedSender.TrustedSender[]
            memory peersToSetTarget = _filterMissingTargets(adapter, allPeers);

        vm.startBroadcast(deployer);

        // 1. Register the adapter as a bridge on xWELL if not already done.
        //    Without a bufferCap > 0, every mint/burn through this adapter
        //    reverts in `_depleteBuffer`/`_replenishBuffer` (MintLimits.sol).
        if (xwell.bufferCap(address(adapter)) == 0) {
            MintLimits.RateLimitMidPointInfo[]
                memory limits = new MintLimits.RateLimitMidPointInfo[](1);
            limits[0] = MintLimits.RateLimitMidPointInfo({
                bridge: address(adapter),
                rateLimitPerSecond: ETH_XWELL_RATE_LIMIT_PER_SECOND,
                bufferCap: ETH_XWELL_BUFFER_CAP
            });
            xwell.addBridges(limits);
        }

        // 2. Route outbound bridge() calls for any peer missing a target.
        //    setTargetAddresses overwrites unconditionally; passing only the
        //    missing entries keeps the calldata minimal and intent obvious.
        if (peersToSetTarget.length > 0) {
            adapter.setTargetAddresses(peersToSetTarget);
        }

        // 3. Hand off ownership to the pauseGuardian (Ownable2Step → pauseGuardian must
        //    later call acceptOwnership on both proxies).
        adapter.transferOwnership(pauseGuardian);
        xwell.transferOwnership(pauseGuardian);

        vm.stopBroadcast();

        _validate(adapter, xwell, allPeers, pauseGuardian);

        console.log(
            "Ethereum WormholeBridgeAdapter wired to Moonbeam/Base/Optimism"
        );
        console.log(
            "xWELL bridge bufferCap:                    ",
            xwell.bufferCap(address(adapter))
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
            "Next step: PAUSE_GUARDIAN must call acceptOwnership() on both proxies."
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

    function _filterMissingSenders(
        WormholeBridgeAdapter adapter,
        WormholeTrustedSender.TrustedSender[] memory peers
    )
        internal
        view
        returns (WormholeTrustedSender.TrustedSender[] memory missing)
    {
        uint256 count;
        bool[] memory keep = new bool[](peers.length);
        for (uint256 i = 0; i < peers.length; i++) {
            if (!adapter.isTrustedSender(peers[i].chainId, peers[i].addr)) {
                keep[i] = true;
                count++;
            }
        }
        missing = new WormholeTrustedSender.TrustedSender[](count);
        uint256 j;
        for (uint256 i = 0; i < peers.length; i++) {
            if (keep[i]) {
                missing[j++] = peers[i];
            }
        }
    }

    function _filterMissingTargets(
        WormholeBridgeAdapter adapter,
        WormholeTrustedSender.TrustedSender[] memory peers
    )
        internal
        view
        returns (WormholeTrustedSender.TrustedSender[] memory missing)
    {
        uint256 count;
        bool[] memory keep = new bool[](peers.length);
        for (uint256 i = 0; i < peers.length; i++) {
            if (adapter.targetAddress(peers[i].chainId) != peers[i].addr) {
                keep[i] = true;
                count++;
            }
        }
        missing = new WormholeTrustedSender.TrustedSender[](count);
        uint256 j;
        for (uint256 i = 0; i < peers.length; i++) {
            if (keep[i]) {
                missing[j++] = peers[i];
            }
        }
    }

    function _validate(
        WormholeBridgeAdapter adapter,
        xWELL xwell,
        WormholeTrustedSender.TrustedSender[] memory peers,
        address pauseGuardian
    ) internal view {
        // Bridge must be registered on xWELL or every mint/burn reverts.
        require(
            xwell.bufferCap(address(adapter)) > 0,
            "xWELL: adapter has zero bufferCap (not a registered bridge)"
        );
        require(
            xwell.rateLimitPerSecond(address(adapter)) > 0,
            "xWELL: adapter has zero rateLimitPerSecond"
        );

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
            adapter.pendingOwner() == pauseGuardian,
            "Adapter: pendingOwner not pauseGuardian"
        );
        require(
            xwell.pendingOwner() == pauseGuardian,
            "xWELL: pendingOwner not pauseGuardian"
        );
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Script} from "@forge-std/Script.sol";
import {console} from "@forge-std/console.sol";

import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ETHEREUM_CHAIN_ID} from "@utils/ChainIds.sol";

/*
 Transfer ownership of Ethereum mainnet xWELL and WormholeBridgeAdapter from
 the deployer EOA to FOUNDATION_MULTISIG.

 Both contracts use OpenZeppelin Ownable2Step, so this script only performs
 STEP 1 of the handover (the deployer-side `transferOwnership` call). The
 multisig must then submit two Safe transactions calling `acceptOwnership()`
 on each proxy to complete the transfer.

 to simulate (no broadcast):
     forge script script/TransferEthereumXWellOwnership.s.sol:TransferEthereumXWellOwnership \
       --rpc-url ethereum -vvvv

 to run:
    forge script script/TransferEthereumXWellOwnership.s.sol:TransferEthereumXWellOwnership \
       --rpc-url ethereum -vvvv --broadcast \
       --private-key $DEPLOYER_PRIVATE_KEY
*/
contract TransferEthereumXWellOwnership is Script {
    function run() public {
        require(
            block.chainid == ETHEREUM_CHAIN_ID,
            "TransferEthereumXWellOwnership: must run on Ethereum mainnet"
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

        vm.startBroadcast(deployer);

        xwell.transferOwnership(multisig);
        adapter.transferOwnership(multisig);

        vm.stopBroadcast();

        // Pending owner is set; acceptance happens off-chain from the multisig.
        require(
            xwell.pendingOwner() == multisig,
            "xWELL: pendingOwner did not update"
        );
        require(
            adapter.pendingOwner() == multisig,
            "WormholeBridgeAdapter: pendingOwner did not update"
        );

        console.log(
            "xWELL_PROXY pendingOwner set to:                   ",
            multisig
        );
        console.log(
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pendingOwner set to: ",
            multisig
        );
        console.log(
            "Next step: FOUNDATION_MULTISIG must call acceptOwnership() on both proxies."
        );
    }
}

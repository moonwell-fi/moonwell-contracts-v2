//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@protocol/utils/ChainIds.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

import {MarketAddV2} from "proposals/templates/MarketAddV2.sol";
import {ITemporalGovernor} from "@protocol/governance/ITemporalGovernor.sol";

contract mipb42 is MarketAddV2 {
    using ChainIds for uint256;

    function build(Addresses addresses) public override selectPrimaryFork {
        super.build(addresses);

        vm.selectFork(MOONBEAM_FORK_ID);

        address artemisTimelock = addresses.getAddress(
            "MOONBEAM_TIMELOCK",
            MOONBEAM_CHAIN_ID
        );
        address temporalGovernor = addresses.getAddress(
            "TEMPORAL_GOVERNOR",
            block.chainid.toOptimismChainId()
        );
        address[] memory temporalGovernanceTargets = new address[](1);
        /// add temporal governor to list
        temporalGovernanceTargets[0] = temporalGovernor;

        ITemporalGovernor.TrustedSender[]
            memory temporalGovernanceTrustedSenders = new ITemporalGovernor.TrustedSender[](
                1
            );

        temporalGovernanceTrustedSenders[0] = ITemporalGovernor.TrustedSender({
            chainId: MOONBEAM_WORMHOLE_CHAIN_ID, /// this chainId is 16 (MOONBEAM_WORMHOLE_CHAIN_ID) regardless of testnet or mainnet
            addr: artemisTimelock /// this timelock on this chain
        });

        /// break glass guardian call for adding artemis as an owner of the Temporal Governor

        /// roll back trusted senders to artemis timelock
        /// in reality this just adds the artemis timelock as a trusted sender
        /// a second proposal is needed to revoke the Multichain Governor as a trusted sender
        bytes memory temporalGovernanceCalldata = abi.encodeWithSignature(
            "setTrustedSenders((uint16,address)[])",
            temporalGovernanceTrustedSenders
        );

        bytes memory approvedCalldata = abi.encodeWithSignature(
            "publishMessage(uint32,bytes,uint8)",
            1000,
            abi.encode(
                /// target is temporal governor, this passes intended recipient check
                temporalGovernanceTargets[0],
                /// sets temporal governor target to itself
                temporalGovernanceTargets,
                /// sets values to array filled with 0 values
                new uint256[](1),
                /// sets calldata to a call to the setTrustedSenders((uint16,address)[])
                /// function with artemis timelock as the address and moonbeam wormhole
                /// chain id as the chain id
                temporalGovernanceCalldata
            ),
            200
        );

        _pushAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR_PROXY"),
            abi.encodeWithSignature(
                "updateApprovedCalldata(bytes,bool)",
                approvedCalldata,
                true
            ),
            "Update approved calldata to include Wormhole with Temporal Governor on Optimism"
        );
    }
}

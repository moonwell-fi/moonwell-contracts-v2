//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Addresses} from "@proposals/Addresses.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {GovernanceProposal} from "@proposals/proposalTypes/GovernanceProposal.sol";

contract mipm16 is GovernanceProposal {
    string public constant name = "MIP-M18";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m18/MIP-M18.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function deploy(Addresses addresses, address) public override {}

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
        address multichainGovernorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR"
        );

        // bytes memory wormholeTemporalGovPayload = abi.encodeWithSignature(
        //     "publishMessage(uint32,bytes,uint8)",
        //     nonce,
        //     temporalGovCalldata,
        //     consistencyLevel
        // );
        /// TODO add multichain governor as wormhole trusted sender in temporal governor

        /// transfer ownership of the wormhole bridge adapter on the moonbeam chain to the multichain governor
        _pushGovernanceAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            )
        );

        /// add the multichain governor as a trusted sender in the wormhole bridge adapter on base
        _pushGovernanceAction(
            addresses.getAddress("WORMHOLE_CORE"),
            "Set the admin of the Wormhole Bridge Adapter to the multichain governor",
            abi.encodeWithSignature(
                "publishMessage(address)",
                multichainGovernorAddress
            )
        );

        /// transfer ownership of proxy admin to the multichain governor
        _pushGovernanceAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "Set the admin of the Chainlink Oracle to the multichain governor",
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            )
        );

        /// begin transfer of ownership of the xwell token to the multichain governor
        /// This one has to go through Temporal Governance
        _pushGovernanceAction(
            addresses.getAddress("xWELL_PROXY"),
            "Set the pending admin of the xWELL Token to the multichain governor",
            abi.encodeWithSignature(
                "transferOwnership(address)",
                multichainGovernorAddress
            )
        );

        /// transfer ownership of chainlink oracle
        _pushGovernanceAction(
            addresses.getAddress("CHAINLINK_ORACLE"),
            "Set the admin of the Chainlink Oracle to the multichain governor",
            abi.encodeWithSignature(
                "setAdmin(address)",
                multichainGovernorAddress
            )
        );

        /// transfer emissions manager of safety module
        _pushGovernanceAction(
            addresses.getAddress("stkWELL"),
            "Set the emissions config of the Safety Module to the multichain governor",
            abi.encodeWithSignature(
                "setEmissionsManager(address)",
                multichainGovernorAddress
            )
        );

        /// set pending admin of comptroller
        _pushGovernanceAction(
            addresses.getAddress("COMPTROLLER"),
            "Set the pending owner of the comptroller to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        /// set pending admin of the vesting contract
        _pushGovernanceAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            "Set the pending admin of the vesting contract to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        /// set funds admin of ecosystem reserve controller
        /// TODO double check that the ecosystem reserve controller is the correct contract
        _pushGovernanceAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            "Set the pending admin of the vesting contract to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        /// set pending admin of the MTokens

        _pushGovernanceAction(
            addresses.getAddress("madWBTC"),
            "Set the pending owner of madWBTC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("madWETH"),
            "Set the pending owner of madWETH to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("madUSDC"),
            "Set the pending owner of madUSDC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MOONWELL_mwBTC"),
            "Set the pending owner of MOONWELL_mwBTC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MOONWELL_mETH"),
            "Set the pending owner of MOONWELL_mETH to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MOONWELL_mUSDC"),
            "Set the pending owner of MOONWELL_mUSDC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MGLIMMER"),
            "Set the pending owner of MGLIMMER to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MDOT"),
            "Set the pending owner of MDOT to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MUSDT"),
            "Set the pending owner of MUSDT to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MFRAX"),
            "Set the pending owner of MFRAX to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MUSDC"),
            "Set the pending owner of MUSDC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("MXCUSDC"),
            "Set the pending owner of MXCUSDC to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );

        _pushGovernanceAction(
            addresses.getAddress("METHWH"),
            "Set the pending owner of METHWH to the multichain governor",
            abi.encodeWithSignature(
                "_setPendingAdmin(address)",
                multichainGovernorAddress
            )
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    function run(Addresses addresses, address) public override {
        /// @dev enable debugging
        setDebug(true);

        _simulateGovernanceActions(
            addresses.getAddress("MOONBEAM_TIMELOCK"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            address(this)
        );
    }

    function validate(Addresses addresses, address) public override {
        /// TODO validate that pending owners have been set where appropriate
        /// TODO validate that new admin/owner has been set where appropriate
    }
}

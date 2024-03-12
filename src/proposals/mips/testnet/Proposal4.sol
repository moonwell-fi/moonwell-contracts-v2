//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";
import {ITokenSaleDistributorProxy} from "../../../tokensale/ITokenSaleDistributorProxy.sol";
import {Timelock} from "@protocol/Governance/deprecated/Timelock.sol";
import {Addresses} from "@proposals/Addresses.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";

//- Accept distributor admin on Artemis,
//- Accept well pending admin
//- Accept bridge adapter pending admin
contract Proposal4 is HybridProposal {
    string public constant name = "PROPOSAL_3";

    constructor() {
        _setProposalDescription(
            bytes(
                "Accept distributor admin on Artemis, Accept well pending admin, Accept bridge adapter pending admin"
            )
        );
    }

    /// @notice proposal's actions mostly happen on moonbeam
    function primaryForkId() public view override returns (uint256) {
        return moonbeamForkId;
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        _pushHybridAction(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept admin of the Wormhole Bridge Adapter as Artemis Timelock",
            true
        );

        _pushHybridAction(
            addresses.getAddress("xWELL_PROXY"),
            abi.encodeWithSignature("acceptOwnership()"),
            "Accept owner of the xWELL Token as Artemis Timelock",
            true
        );

        _pushHybridAction(
            addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY"),
            abi.encodeWithSignature("acceptPendingAdmin()"),
            "Accept admin of the Token Sale Distributor as Artemis Timelock",
            true
        );
    }

    function run(Addresses addresses, address) public override {
        vm.selectFork(moonbeamForkId);

        _runMoonbeamArtemisGovernor(
            addresses.getAddress("WORMHOLE_CORE"),
            addresses.getAddress("ARTEMIS_GOVERNOR"),
            addresses.getAddress("WELL"),
            address(1000000000)
        );
    }

    function validate(Addresses addresses, address) public override {
        address timelock = addresses.getAddress("MOONBEAM_TIMELOCK");

        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).pendingOwner(),
            address(0),
            "WORMHOLE_BRIDGE_ADAPTER_PROXY pending owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
            ).owner(),
            timelock,
            "WORMHOLE_BRIDGE_ADAPTER_PROXY owner incorrect"
        );

        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .owner(),
            timelock,
            "xWELL_PROXY owner incorrect"
        );
        assertEq(
            Ownable2StepUpgradeable(addresses.getAddress("xWELL_PROXY"))
                .pendingOwner(),
            address(0),
            "xWELL_PROXY pending owner incorrect"
        );

        assertEq(
            ITokenSaleDistributorProxy(
                addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY")
            ).admin(),
            timelock,
            "TOKEN_SALE_DISTRIBUTOR_PROXY owner incorrect"
        );
        assertEq(
            ITokenSaleDistributorProxy(
                addresses.getAddress("TOKEN_SALE_DISTRIBUTOR_PROXY")
            ).pendingAdmin(),
            address(0),
            "TOKEN_SALE_DISTRIBUTOR_PROXY pending owner incorrect"
        );
    }
}

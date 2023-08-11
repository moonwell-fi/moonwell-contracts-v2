//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {ERC20} from "solmate/tokens/ERC20.sol";

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {MErc20} from "@protocol/MErc20.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";
import {Comptroller as IComptroller} from "@protocol/Comptroller.sol";

contract mip01 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIP01";

    constructor() {
        _setNonce(3);
    }

    /// @notice deploy the new MWETH logic contract and the ERC4626 Wrappers
    function deploy(Addresses addresses, address) public {
        MWethDelegate mWethLogic = new MWethDelegate();
        addresses.addAddress("MWETH_IMPLEMENTATION", address(mWethLogic));
    }

    function afterDeploy(Addresses addresses, address) public {}

    function afterDeploySetup(Addresses addresses) public {}

    function build(Addresses addresses) public {
        /// point weth mToken to new logic contract
        _pushCrossChainAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setImplementation(address,bool,bytes)",
                addresses.getAddress("MWETH_IMPLEMENTATION"),
                true,
                ""
            ),
            "Point Moonwell WETH to new logic contract"
        );
    }

    function run(Addresses addresses, address) public {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure {}

    function validate(Addresses addresses, address) public {
        assertTrue(
            addresses.getAddress("MOONWELL_WETH") != address(0),
            "MOONWELL_WETH not set"
        );
        assertTrue(
            addresses.getAddress("MWETH_IMPLEMENTATION") != address(0),
            "MWETH_IMPLEMENTATION not set"
        );
        assertTrue(
            addresses.getAddress("WETH_ROUTER") != address(0),
            "WETH_ROUTER not set"
        );

        WETHRouter router = WETHRouter(
            payable(addresses.getAddress("WETH_ROUTER"))
        );
        assertEq(
            address(router.weth()),
            addresses.getAddress("WETH"),
            "WETH_ROUTER weth not set"
        );
        assertEq(
            address(router.mToken()),
            addresses.getAddress("MOONWELL_WETH"),
            "WETH_ROUTER mWeth not set"
        );

        /// ensure that the mWeth implementation is set correctly
        MErc20Delegator mWeth = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        assertEq(
            mWeth.implementation(),
            addresses.getAddress("MWETH_IMPLEMENTATION"),
            "MOONWELL_WETH implementation not correctly set"
        );
        assertEq(mWeth.admin(), addresses.getAddress("TEMPORAL_GOVERNOR")); /// ensure temporal gov is still admin
    }
}

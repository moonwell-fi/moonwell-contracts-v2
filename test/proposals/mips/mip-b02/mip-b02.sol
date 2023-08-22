//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {WETH9} from "@protocol/router/IWETH.sol";
import {Configs} from "@test/proposals/Configs.sol";
import {ChainIds} from "@test/utils/ChainIds.sol";
import {Proposal} from "@test/proposals/proposalTypes/Proposal.sol";
import {Addresses} from "@test/proposals/Addresses.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {CrossChainProposal} from "@test/proposals/proposalTypes/CrossChainProposal.sol";


/// how to generate calldata: 
/// first set up environment variables:
/*
export DEPLOY=false
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=false
export DO_AFTER_DEPLOY_SETUP=false
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/

/// forge script test/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv

contract mipb02 is Proposal, CrossChainProposal, ChainIds, Configs {
    string public constant name = "MIP-b02";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    constructor() {
        _setNonce(2);

        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./test/proposals/mips/mip-b02/MIP-B02.md")
        );

        _setProposalDescription(proposalDescription);
    }

    /// @notice deploy the new MWETH logic contract and the ERC4626 Wrappers
    function deploy(Addresses addresses, address) public override {
        MWethDelegate mWethLogic = new MWethDelegate();
        addresses.addAddress("MWETH_IMPLEMENTATION", address(mWethLogic));
    }

    function afterDeploy(Addresses addresses, address) public override {}

    function afterDeploySetup(Addresses addresses) public override {}

    function build(Addresses addresses) public override {
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

    function run(Addresses addresses, address) public override {
        _simulateCrossChainActions(addresses.getAddress("TEMPORAL_GOVERNOR"));
    }

    function printCalldata(Addresses addresses) public {
        printActions(
            addresses.getAddress("TEMPORAL_GOVERNOR"),
            addresses.getAddress("WORMHOLE_CORE")
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public override {
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

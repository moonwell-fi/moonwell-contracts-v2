//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {BASE_FORK_ID} from "@utils/ChainIds.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {HybridProposal} from "@proposals/proposalTypes/HybridProposal.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// how to generate calldata:
/// first set up environment variables:
/*
export DO_DEPLOY=false
export DO_AFTER_DEPLOY=false
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/

/// forge script src/proposals/mips/mip-b02/mip-b02.sol:mipb02 --rpc-url base -vvvvv

contract mipb02 is HybridProposal, Configs {
    string public constant override name = "MIP-B02";
    uint256 public constant timestampsPerYear = 60 * 60 * 24 * 365;
    uint256 public constant SCALE = 1e18;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-b02/MIP-B02.md")
        );

        _setProposalDescription(proposalDescription);

        nonce = 2;
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    /// @notice deploy the new MWETH logic contract and the ERC4626 Wrappers
    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("WETH_UNWRAPPER")) {
            MWethDelegate mWethLogic = new MWethDelegate(
                addresses.getAddress("WETH_UNWRAPPER")
            );

            addresses.addAddress("MWETH_IMPLEMENTATION", address(mWethLogic));
        }
    }

    function build(Addresses addresses) public override {
        /// point weth mToken to new logic contract
        _pushAction(
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

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert that the new interest rate model is set correctly
    /// and that the interest rate model parameters are set correctly
    function validate(Addresses addresses, address) public view override {
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

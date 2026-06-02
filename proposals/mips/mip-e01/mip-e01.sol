//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {Configs} from "@proposals/Configs.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {ETHEREUM_FORK_ID} from "@utils/ChainIds.sol";
import {WethUnwrapper} from "@protocol/WethUnwrapper.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {HybridProposalV2} from "@proposals/proposalTypes/HybridProposalV2.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @notice MIP-E01 — enable native ETH redeem/borrow on the Ethereum MOONWELL_WETH market.
/// Points the WETH mToken delegator implementation at MWethDelegate, which overrides
/// `doTransferOut` to forward the underlying WETH to a WethUnwrapper that withdraws raw
/// ETH and sends it to the user. Deposit and repay in native ETH already work via the
/// WETH_ROUTER deployed in MIP-E00; this proposal completes the redeem/borrow side.
///
/// how to generate calldata / run a standalone simulation against a mainnet fork:
/*
export DO_DEPLOY=true
export DO_AFTER_DEPLOY=false
export DO_BUILD=true
export DO_RUN=true
export DO_TEARDOWN=false
export DO_VALIDATE=true
*/
/// forge script proposals/mips/mip-e01/mip-e01.sol:mipe01 --rpc-url ethereum -vvv

contract mipe01 is HybridProposalV2, Configs {
    string public constant override name = "MIP-E01";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-e01/MIP-E01.md")
        );

        _setProposalDescription(proposalDescription);

        nonce = 2;
    }

    function primaryForkId() public pure override returns (uint256) {
        return ETHEREUM_FORK_ID;
    }

    /// @notice deploy the WethUnwrapper and the MWethDelegate logic contract on Ethereum.
    /// Both are inert until governance points the WETH market at the new implementation
    /// in build().
    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("WETH_UNWRAPPER")) {
            WethUnwrapper unwrapper = new WethUnwrapper(
                addresses.getAddress("WETH")
            );

            addresses.addAddress("WETH_UNWRAPPER", address(unwrapper));
        }

        if (!addresses.isAddressSet("MWETH_IMPLEMENTATION")) {
            MWethDelegate mWethLogic = new MWethDelegate(
                addresses.getAddress("WETH_UNWRAPPER")
            );

            addresses.addAddress("MWETH_IMPLEMENTATION", address(mWethLogic));
        }
    }

    function build(Addresses addresses) public override {
        /// point the WETH mToken to the new MWethDelegate logic contract.
        /// MOONWELL_WETH.admin() is MULTICHAIN_GOVERNOR_V2_PROXY on Ethereum
        /// (transferred to the governor in MIP-E00), which is the executor of
        /// this HybridProposalV2 — so the admin-gated _setImplementation call
        /// succeeds.
        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setImplementation(address,bool,bytes)",
                addresses.getAddress("MWETH_IMPLEMENTATION"),
                true,
                ""
            ),
            "Point Moonwell WETH (Ethereum) to the MWethDelegate logic contract"
        );
    }

    function teardown(Addresses addresses, address) public pure override {}

    /// @notice assert the WETH market is wired to the unwrapping delegate and that the
    /// deposit-side router and admin are unchanged.
    function validate(Addresses addresses, address) public override {
        assertTrue(
            addresses.getAddress("MOONWELL_WETH") != address(0),
            "MOONWELL_WETH not set"
        );
        assertTrue(
            addresses.getAddress("WETH_UNWRAPPER") != address(0),
            "WETH_UNWRAPPER not set"
        );
        assertTrue(
            addresses.getAddress("MWETH_IMPLEMENTATION") != address(0),
            "MWETH_IMPLEMENTATION not set"
        );

        /// the unwrapper references the canonical WETH
        assertEq(
            WethUnwrapper(payable(addresses.getAddress("WETH_UNWRAPPER")))
                .weth(),
            addresses.getAddress("WETH"),
            "WETH_UNWRAPPER weth mismatch"
        );

        /// the new delegate references the deployed unwrapper
        assertEq(
            MWethDelegate(addresses.getAddress("MWETH_IMPLEMENTATION"))
                .wethUnwrapper(),
            addresses.getAddress("WETH_UNWRAPPER"),
            "MWETH_IMPLEMENTATION unwrapper mismatch"
        );

        /// deposit/repay-in-ETH path: WETH_ROUTER (deployed in MIP-E00) stays wired to
        /// this market
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
            "WETH_ROUTER mToken not set"
        );

        /// the WETH market now points to the MWethDelegate, admin unchanged
        MErc20Delegator mWeth = MErc20Delegator(
            payable(addresses.getAddress("MOONWELL_WETH"))
        );
        assertEq(
            mWeth.implementation(),
            addresses.getAddress("MWETH_IMPLEMENTATION"),
            "MOONWELL_WETH implementation not correctly set"
        );
        assertEq(
            mWeth.admin(),
            addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"),
            "MOONWELL_WETH admin changed"
        ); /// ensure the MultichainGovernorV2 is still admin
    }
}

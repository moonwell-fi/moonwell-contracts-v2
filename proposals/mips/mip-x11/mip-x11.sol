//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Ownable2StepUpgradeable} from "@openzeppelin-contracts-upgradeable/contracts/access/Ownable2StepUpgradeable.sol";

import "@utils/ChainIds.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {WETHRouter} from "@protocol/router/WETHRouter.sol";
import {MWethDelegate} from "@protocol/MWethDelegate.sol";
import {MErc20Delegator} from "@protocol/MErc20Delegator.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract mipx11 is HybridProposal {
    string public constant override name = "MIP-X11";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x11/x11.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    /// @notice deploy the new MWETH logic contract and the ERC4626 Wrappers
    function deploy(Addresses addresses, address) public override {
        if (!addresses.isAddressSet("NEW_MWETH_IMPLEMENTATION")) {
            MWethDelegate mWethLogic = new MWethDelegate(
                addresses.getAddress("WETH_UNWRAPPER")
            );

            addresses.addAddress(
                "NEW_MWETH_IMPLEMENTATION",
                address(mWethLogic)
            );
        }
    }

    function build(Addresses addresses) public override {
        /// point weth mToken to new logic contract
        _pushAction(
            addresses.getAddress("MOONWELL_WETH"),
            abi.encodeWithSignature(
                "_setImplementation(address,bool,bytes)",
                addresses.getAddress("NEW_MWETH_IMPLEMENTATION"),
                true,
                ""
            ),
            "Point Moonwell WETH to new logic contract"
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(BASE_FORK_ID);

        assertTrue(
            addresses.getAddress("MOONWELL_WETH") != address(0),
            "MOONWELL_WETH not set"
        );

        /// check is implicit in the calling of this function
        assertTrue(
            addresses.getAddress("NEW_MWETH_IMPLEMENTATION") != address(0),
            "NEW_MWETH_IMPLEMENTATION not set"
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
            addresses.getAddress("NEW_MWETH_IMPLEMENTATION"),
            "MOONWELL_WETH implementation not correctly set"
        );
        assertEq(mWeth.admin(), addresses.getAddress("TEMPORAL_GOVERNOR")); /// ensure temporal gov is still admin
    }
}

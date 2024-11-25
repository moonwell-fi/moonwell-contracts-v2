//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";

contract mipx08 is HybridProposal {
    string public constant override name = "MIP-X07";

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x07/x07.md")
        );

        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function build(Addresses addresses) public override {
        _pushAction(
            addresses.getAddress("MULTICHAIN_GOVERNOR", MOONBEAM_CHAIN_ID),
            abi.encodeWithSignature("updateMaxUserLiveProposals(uint256)", 2),
            "Set the maximum number of live proposals to 2",
            ActionType.Moonbeam
        );
        _pushAction(
            addresses.getAddress("xWELL_PROXY", BASE_CHAIN_ID),
            abi.encodeWithSignature(
                "transferFrom(address,address,uint256)",
                addresses.getAddress("FOUNDATION_MULTISIG"),
                addresses.getAddress("MOONWELL_METAMORPHO_URD"),
                16_000_000e18
            ),
            "Send 16M WELL to Morpho URD contract",
            ActionType.Base
        );
    }

    function validate(Addresses addresses, address) public override {
        vm.selectFork(MOONBEAM_FORK_ID);

        MultichainGovernor governor = MultichainGovernor(
            addresses.getAddress("MULTICHAIN_GOVERNOR", MOONBEAM_CHAIN_ID)
        );

        vm.assertEq(
            governor.maxUserLiveProposals(),
            2,
            "Max user live proposals not set correctly"
        );

        vm.selectFork(BASE_FORK_ID);

        IERC20 well = IERC20(
            addresses.getAddress("xWELL_PROXY", BASE_CHAIN_ID)
        );

        vm.assertEq(
            well.balanceOf(addresses.getAddress("MOONWELL_METAMORPHO_URD")),
            16_000_000e18,
            "16M WELL not sent to Morpho URD"
        );
    }
}

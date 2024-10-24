//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {etch} from "@proposals/utils/PrecompileEtching.sol";
import {IStakedWell} from "@protocol/IStakedWell.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {MOONBEAM_FORK_ID, MOONBASE_CHAIN_ID} from "@utils/ChainIds.sol";

/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// src/proposals/mips/mip-m40/mip-m40.sol:mipm40
contract mipm40 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-M40";
    uint256 public constant COOLDOWN_SECONDS = 7 days;

    mapping(address => uint256) public startingBalances;

    address[] public users;

    uint256 public startingTotalSupply;
    address public stakedToken;
    address public rewardsVault;
    address public emissionsManager;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./src/proposals/mips/mip-m40/MIP-M40.md")
        );
        _setProposalDescription(proposalDescription);

        users.push(0x98952d189C6FFB802A7292180aFcb33Cc618D0a0);
        users.push(0x053172Febe1C416dd382041a9aAB50Fc7bCDea1c);
        users.push(0xA07094ffd0BE84CD14C2b274986A5491b8e3EBd1);
        users.push(0x3b8bF66F9920652DD2700A8538EDbdF3D6326131);
        users.push(0xb34491017b3f0C567496E8EFE6970c44CbB2A8Fd);
        users.push(0xb13b8a0744a06C1D0e59B297B1893619A4DC4017);
    }

    function primaryForkId() public pure override returns (uint256) {
        return MOONBEAM_FORK_ID;
    }

    function deploy(Addresses addresses, address) public override {
        address implementation = deployCode(
            "artifacts/foundry/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
        );

        require(
            implementation != address(0),
            "MIP-M40: failed to deploy STK_GOVTOKEN_IMPL"
        );

        addresses.addAddress("STK_GOVTOKEN_IMPL", implementation);
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Moonbeam actions

        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL")
            ),
            "Upgrade Safety Module Implementation",
            ActionType.Moonbeam
        );

        _pushAction(
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            abi.encodeWithSignature(
                "setCoolDownSeconds(uint256)",
                COOLDOWN_SECONDS
            ),
            "Set the cooldown period for stkWELL on Moonbeam",
            ActionType.Moonbeam
        );
    }

    function run(Addresses addresses, address) public override {
        /// safety check to ensure no base actions are run
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 0,
            "MIP-M40: should have no base actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Optimism) == 0,
            "MIP-M40: should have no optimism actions"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 2,
            "MIP-M40: should have one moonbeam action"
        );

        for (uint256 i = 0; i < users.length; i++) {
            startingBalances[users[i]] = IStakedWell(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            ).balanceOf(users[i]);
        }

        startingTotalSupply = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        ).totalSupply();

        stakedToken = address(
            IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                .STAKED_TOKEN()
        );
        rewardsVault = address(
            IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                .REWARDS_VAULT()
        );
        emissionsManager = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        ).EMISSION_MANAGER();

        /// only run actions on moonbeam
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        {
            IStakedWell stakedWell = IStakedWell(
                addresses.getAddress("STK_GOVTOKEN_PROXY")
            );

            vm.assertEq(
                stakedWell.COOLDOWN_SECONDS(),
                COOLDOWN_SECONDS,
                "Moonbeam cooldown period not set correctly"
            );
        }

        validateProxy(
            vm,
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            addresses.getAddress("STK_GOVTOKEN_IMPL"),
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            "STK_GOVTOKEN impl upgrade validation"
        );

        for (uint256 i = 0; i < users.length; i++) {
            assertEq(
                startingBalances[users[i]],
                IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                    .balanceOf(users[i]),
                "balances not the same after ugprade"
            );
        }

        assertEq(
            startingTotalSupply,
            IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                .totalSupply(),
            "total supply not the same after upgrade"
        );
        assertEq(
            stakedToken,
            address(
                IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                    .STAKED_TOKEN()
            ),
            "staked token not the same after upgrade"
        );
        assertEq(
            rewardsVault,
            address(
                IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                    .REWARDS_VAULT()
            ),
            "rewards vault not the same after upgrade"
        );
        assertEq(
            emissionsManager,
            IStakedWell(addresses.getAddress("STK_GOVTOKEN_PROXY"))
                .EMISSION_MANAGER(),
            "emissions manager not the same after upgrade"
        );
    }
}

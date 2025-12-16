//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";

import {IStakedWell} from "@protocol/IStakedWell.sol";
import {validateProxy} from "@proposals/utils/ProxyUtils.sol";
import {ProposalActions} from "@proposals/utils/ProposalActions.sol";
import {MOONBEAM_FORK_ID, BASE_FORK_ID, OPTIMISM_FORK_ID} from "@utils/ChainIds.sol";
import {ParameterValidation} from "@proposals/utils/ParameterValidation.sol";
import {HybridProposal, ActionType} from "@proposals/proposalTypes/HybridProposal.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";

/// @title MIP-X39: Remove configureAsset from stkWELL
/// @notice This proposal upgrades the stkWELL implementation on all chains (Base, Optimism, Moonbeam)
///         to remove the buggy configureAsset function for security reasons.
///
/// DO_VALIDATE=true DO_DEPLOY=true DO_PRINT=true DO_BUILD=true DO_RUN=true forge script
/// proposals/mips/mip-x39/mip-x39.sol:mipx39
contract mipx39 is HybridProposal, ParameterValidation {
    using ProposalActions for *;

    string public constant override name = "MIP-X39";

    /// @dev Sample users for validation - ensures balances and voting power are preserved
    mapping(uint256 => address[]) public chainUsers;

    /// @dev Storage for validation
    mapping(uint256 => mapping(address => uint256)) public startingBalances;
    mapping(uint256 => mapping(address => uint256)) public startingVotingPower;
    mapping(uint256 => uint256) public startingTotalSupply;
    mapping(uint256 => address) public stakedToken;
    mapping(uint256 => address) public rewardsVault;
    mapping(uint256 => address) public emissionsManager;

    constructor() {
        bytes memory proposalDescription = abi.encodePacked(
            vm.readFile("./proposals/mips/mip-x39/x39.md")
        );
        _setProposalDescription(proposalDescription);
    }

    function primaryForkId() public pure override returns (uint256) {
        return BASE_FORK_ID;
    }

    function beforeSimulationHook(Addresses addresses) public override {
        // Store starting state for Base
        _storeStartingState(addresses, BASE_FORK_ID);

        // Store starting state for Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _storeStartingState(addresses, OPTIMISM_FORK_ID);

        // Store starting state for Moonbeam
        vm.selectFork(MOONBEAM_FORK_ID);
        _storeStartingState(addresses, MOONBEAM_FORK_ID);

        // Return to primary fork
        vm.selectFork(BASE_FORK_ID);
    }

    function _storeStartingState(Addresses addresses, uint256 forkId) internal {
        IStakedWell stkWell = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        startingTotalSupply[forkId] = stkWell.totalSupply();
        stakedToken[forkId] = address(stkWell.STAKED_TOKEN());
        rewardsVault[forkId] = address(stkWell.REWARDS_VAULT());
        emissionsManager[forkId] = stkWell.EMISSION_MANAGER();
    }

    function deploy(Addresses addresses, address) public override {
        // Deploy new implementation on Base
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL")) {
            address implementation = deployCode(
                "deprecated/artifacts/StakedWell.sol/StakedWell.json"
            );

            require(
                implementation != address(0),
                "MIP-X39: failed to deploy STK_GOVTOKEN_IMPL on Base"
            );

            addresses.addAddress("STK_GOVTOKEN_IMPL", implementation);
        }

        // Deploy new implementation on Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL")) {
            address implementation = deployCode(
                "deprecated/artifacts/StakedWell.sol/StakedWell.json"
            );

            require(
                implementation != address(0),
                "MIP-X39: failed to deploy STK_GOVTOKEN_IMPL on Optimism"
            );

            addresses.addAddress("STK_GOVTOKEN_IMPL", implementation);
        }

        // Deploy new implementation on Moonbeam
        vm.selectFork(MOONBEAM_FORK_ID);
        if (!addresses.isAddressSet("STK_GOVTOKEN_IMPL")) {
            address implementation = deployCode(
                "deprecated/artifacts/StakedWellMoonbeam.sol/StakedWellMoonbeam.json"
            );

            require(
                implementation != address(0),
                "MIP-X39: failed to deploy STK_GOVTOKEN_IMPL on Moonbeam"
            );

            addresses.addAddress("STK_GOVTOKEN_IMPL", implementation);
        }

        // Return to primary fork
        vm.selectFork(BASE_FORK_ID);
    }

    /// run this action through the Multichain Governor
    function build(Addresses addresses) public override {
        /// Base action - upgrade via Temporal Governor
        _pushAction(
            addresses.getAddress("PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL")
            ),
            "Upgrade stkWELL implementation on Base",
            ActionType.Base
        );

        /// Optimism action - upgrade via Temporal Governor
        vm.selectFork(OPTIMISM_FORK_ID);
        _pushAction(
            addresses.getAddress("PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL")
            ),
            "Upgrade stkWELL implementation on Optimism",
            ActionType.Optimism
        );

        /// Moonbeam action - direct upgrade via proxy admin
        vm.selectFork(MOONBEAM_FORK_ID);
        _pushAction(
            addresses.getAddress("MOONBEAM_PROXY_ADMIN"),
            abi.encodeWithSignature(
                "upgrade(address,address)",
                addresses.getAddress("STK_GOVTOKEN_PROXY"),
                addresses.getAddress("STK_GOVTOKEN_IMPL")
            ),
            "Upgrade stkWELL implementation on Moonbeam",
            ActionType.Moonbeam
        );

        // Return to primary fork
        vm.selectFork(BASE_FORK_ID);
    }

    function run(
        Addresses addresses,
        address
    ) public override mockHook(addresses) {
        /// safety checks
        require(
            actions.proposalActionTypeCount(ActionType.Base) == 1,
            "MIP-X39: should have one Base action"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Optimism) == 1,
            "MIP-X39: should have one Optimism action"
        );

        require(
            actions.proposalActionTypeCount(ActionType.Moonbeam) == 1,
            "MIP-X39: should have one Moonbeam action"
        );

        /// run actions on all chains
        _runMoonbeamMultichainGovernor(addresses, address(1000000000));
    }

    function validate(Addresses addresses, address) public view override {
        // Validate Base
        _validateChain(addresses, BASE_FORK_ID, "PROXY_ADMIN");

        // Validate Optimism
        vm.selectFork(OPTIMISM_FORK_ID);
        _validateChain(addresses, OPTIMISM_FORK_ID, "PROXY_ADMIN");

        // Validate Moonbeam
        vm.selectFork(MOONBEAM_FORK_ID);
        _validateChain(addresses, MOONBEAM_FORK_ID, "MOONBEAM_PROXY_ADMIN");

        // Return to primary fork
        vm.selectFork(BASE_FORK_ID);
    }

    function _validateChain(
        Addresses addresses,
        uint256 forkId,
        string memory proxyAdminKey
    ) internal view {
        // Validate proxy points to new implementation
        validateProxy(
            vm,
            addresses.getAddress("STK_GOVTOKEN_PROXY"),
            addresses.getAddress("STK_GOVTOKEN_IMPL"),
            addresses.getAddress(proxyAdminKey),
            "STK_GOVTOKEN impl upgrade validation"
        );

        IStakedWell stkWell = IStakedWell(
            addresses.getAddress("STK_GOVTOKEN_PROXY")
        );

        // Validate total supply preserved
        assertEq(
            startingTotalSupply[forkId],
            stkWell.totalSupply(),
            "total supply not the same after upgrade"
        );

        // Validate staked token preserved
        assertEq(
            stakedToken[forkId],
            address(stkWell.STAKED_TOKEN()),
            "staked token not the same after upgrade"
        );

        // Validate rewards vault preserved
        assertEq(
            rewardsVault[forkId],
            address(stkWell.REWARDS_VAULT()),
            "rewards vault not the same after upgrade"
        );

        // Validate emission manager preserved
        assertEq(
            emissionsManager[forkId],
            stkWell.EMISSION_MANAGER(),
            "emissions manager not the same after upgrade"
        );
    }
}

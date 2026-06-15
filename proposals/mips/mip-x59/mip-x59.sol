//SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@utils/ChainIds.sol";

import {xWELLBridgeFeePayer} from "@protocol/xWELL/xWELLBridgeFeePayer.sol";
import {RewardsDistributionV2Template} from "@proposals/templates/RewardsDistributionV2.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {ActionType, ProposalAction} from "@proposals/proposalTypes/IProposal.sol";

interface IAdminTwoStep {
    function admin() external view returns (address);

    function pendingAdmin() external view returns (address);
}

interface IComptrollerMarkets {
    function getAllMarkets() external view returns (address[] memory);
}

/// @title MIP-X59
/// @notice Rewards distribution for the 2026-06-15 -> 2026-07-15 epoch.
///         First rewards MIP executed from Ethereum (MultichainGovernorV2):
///         - chain 1 is the source chain: FOUNDATION_MULTISIG funds the
///           governor (xWELL bridged to the Base Temporal Governor via the
///           WormholeBridgeAdapter on-chain-quoted path) and funds the
///           Ethereum MRD directly via transferFrom
///         - Base/Optimism remain external destination chains
///         - Moonbeam is a pure destination chain in wind-down mode
///         The template's beforeSimulationHook asserts the LIVE foundation
///         approval and balance on the fork (no mocking): the foundation's
///         xWELL allowance to the V2 governor is already in place on mainnet
///         and must cover the epoch outflow, so no extra hook is needed here.
///
///         This MIP also completes the MIP-X58 Moonbeam admin migration:
///         X58 called _setPendingAdmin(TEMPORAL_GOVERNOR) on the Unitroller
///         and every mToken, but the two-step handoff was never finished, so
///         admin is still the old MultichainGovernor and the comptroller
///         rejects _setRewardSpeed from the Temporal Governor. Before the
///         template's Moonbeam actions, this proposal pushes _acceptAdmin()
///         (executed by the Temporal Governor, which is the pendingAdmin) on
///         the Unitroller and on every market whose handoff is still pending.
contract mipx59 is RewardsDistributionV2Template {
    using ChainIds for uint256;

    function name() external pure override returns (string memory) {
        return "MIP-X59";
    }

    /// @notice the full propose() calldata (~37KB across 129 actions) is far
    ///         too large to submit in a single call. The Base bundle alone is
    ///         ~20KB, so it is split into two wormhole chunks and the
    ///         proposal submitted through the governor's init + append
    ///         batching in four calls of ~7-12KB each:
    ///         call 1 = Ethereum actions + Moonbeam bundle (finalize = false)
    ///         call 2 = Base chunk 0
    ///         call 3 = Base chunk 1
    ///         call 4 = Optimism bundle (finalize = true)
    ///
    ///         Base action layout is [0] = TG -> MRD xWELL transfer,
    ///         [1..46] = independent MRD reward speed / end time calls,
    ///         [47..61] = five atomic approve -> accept -> create merkle
    ///         campaign triples. The chunk boundary (32) falls inside the
    ///         independent speed calls, so no dependent sequence is split
    ///         across VAAs. Re-tune the boundary if x59.json is regenerated.
    uint256 public constant BASE_CHUNK_BOUNDARY = 32;

    /// @notice split the Base action bundle into two wormhole payloads
    function chunkCount(
        ActionType actionType
    ) public pure override returns (uint256) {
        return actionType == ActionType.Base ? 2 : 1;
    }

    function chunkActions(
        ActionType actionType,
        uint256 index
    ) public view override returns (ProposalAction[] memory chunk) {
        if (actionType != ActionType.Base) {
            return super.chunkActions(actionType, index);
        }

        ProposalAction[] memory baseActions = getActionsByType(ActionType.Base);
        uint256 start = index == 0 ? 0 : BASE_CHUNK_BOUNDARY;
        uint256 end = index == 0 ? BASE_CHUNK_BOUNDARY : baseActions.length;
        require(end > start && end <= baseActions.length, "x59: bad chunk");

        chunk = new ProposalAction[](end - start);
        for (uint256 i = start; i < end; i++) {
            chunk[i - start] = baseActions[i];
        }
    }

    /// @notice governor action layout is [Ethereum actions..., Moonbeam
    ///         bundle, Base chunk 0, Base chunk 1, Optimism bundle]. The
    ///         Ethereum action count and the Moonbeam _acceptAdmin actions
    ///         depend on live chain state, so indices are computed.
    function batchProposeSplits()
        public
        view
        override
        returns (uint256[] memory splits)
    {
        uint256 ethereumCount = getActionsByType(ActionType.Ethereum).length;

        splits = new uint256[](3);
        splits[0] = ethereumCount + 1; // call 1: Ethereum + Moonbeam bundle
        splits[1] = ethereumCount + 2; // call 2: Base chunk 0
        splits[2] = ethereumCount + 3; // call 3: Base chunk 1
        // call 4: Optimism bundle (finalize = true)
    }

    function deploy(Addresses addresses, address) public virtual override {
        // Canonical deployment of the xWELLBridgeFeePayer: it pays the
        // Wormhole Executor fee from its own pre-funded ETH balance so bridge
        // actions carry zero value (see _buildBridgeOutActions). Running the
        // proposal's deploy step with broadcast deploys it for real; record
        // the printed address as xWELL_BRIDGE_FEE_PAYER in chains/1.json and
        // fund it with a little ETH (~0.01 ETH covers years of epochs).
        // Once recorded, this block becomes a no-op; it can be removed
        // entirely when the adapter drops its exact msg.value requirement
        // (https://github.com/moonwell-fi/moonwell-contracts-v2/issues/667).

        if (!addresses.isAddressSet("xWELL_BRIDGE_FEE_PAYER")) {
            xWELLBridgeFeePayer feePayer = new xWELLBridgeFeePayer(
                addresses.getAddress("xWELL_PROXY"),
                addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY"),
                addresses.getAddress("MULTICHAIN_GOVERNOR_V2_PROXY"),
                addresses.getAddress("FOUNDATION_MULTISIG")
            );

            addresses.addAddress("xWELL_BRIDGE_FEE_PAYER", address(feePayer));
        }
    }

    function build(Addresses addresses) public override {
        // Accept actions must precede the template's Moonbeam reward-speed
        // actions inside the Moonbeam VAA bundle (actions execute in push order).
        _buildAcceptMoonbeamAdmin(addresses);

        super.build(addresses);
    }

    function _buildAcceptMoonbeamAdmin(Addresses addresses) internal {
        vm.selectFork(MOONBEAM_FORK_ID);

        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address unitroller = addresses.getAddress("UNITROLLER");

        if (
            IAdminTwoStep(unitroller).pendingAdmin() == temporalGovernor &&
            IAdminTwoStep(unitroller).admin() != temporalGovernor
        ) {
            _pushAction(
                unitroller,
                abi.encodeWithSignature("_acceptAdmin()"),
                "Accept the X58 admin handoff on the Unitroller (old MultichainGovernor -> Temporal Governor)"
            );
        }

        address[] memory markets = IComptrollerMarkets(unitroller)
            .getAllMarkets();

        for (uint256 i = 0; i < markets.length; i++) {
            // Tolerate markets without the two-step admin surface
            try IAdminTwoStep(markets[i]).pendingAdmin() returns (
                address pending
            ) {
                if (
                    pending == temporalGovernor &&
                    IAdminTwoStep(markets[i]).admin() != temporalGovernor
                ) {
                    _pushAction(
                        markets[i],
                        abi.encodeWithSignature("_acceptAdmin()"),
                        string.concat(
                            "Accept the X58 admin handoff on market ",
                            vm.toString(markets[i])
                        )
                    );
                }
            } catch {}
        }
    }

    function validate(Addresses addresses, address deployer) public override {
        super.validate(addresses, deployer);

        // The X58 handoff must be complete after execution
        vm.selectFork(MOONBEAM_FORK_ID);
        address temporalGovernor = addresses.getAddress("TEMPORAL_GOVERNOR");
        address unitroller = addresses.getAddress("UNITROLLER");

        assertEq(
            IAdminTwoStep(unitroller).admin(),
            temporalGovernor,
            "Unitroller admin must be the Temporal Governor after X59"
        );

        address[] memory markets = IComptrollerMarkets(unitroller)
            .getAllMarkets();
        for (uint256 i = 0; i < markets.length; i++) {
            try IAdminTwoStep(markets[i]).admin() returns (address admin) {
                assertEq(
                    admin,
                    temporalGovernor,
                    string.concat(
                        "market admin must be the Temporal Governor: ",
                        vm.toString(markets[i])
                    )
                );
            } catch {}
        }
    }
}

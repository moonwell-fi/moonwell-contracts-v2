// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import "@forge-std/Test.sol";
import {console} from "@forge-std/console.sol";

import "@utils/ChainIds.sol";
import {Bytes} from "@utils/Bytes.sol";
import {xWELL} from "@protocol/xWELL/xWELL.sol";
import {String} from "@utils/String.sol";
import {Address} from "@utils/Address.sol";
import {Proposal} from "@proposals/Proposal.sol";
import {Networks} from "@proposals/utils/Networks.sol";
import {IWormhole} from "@protocol/wormhole/IWormhole.sol";
import {ProposalMap} from "@test/utils/ProposalMap.sol";
import {Implementation} from "@test/mock/wormhole/Implementation.sol";
import {ProposalChecker} from "@proposals/utils/ProposalChecker.sol";
import {TemporalGovernor} from "@protocol/governance/TemporalGovernor.sol";
import {WormholeBridgeAdapter} from "@protocol/xWELL/WormholeBridgeAdapter.sol";
import {WormholeRelayerAdapter} from "@test/mock/WormholeRelayerAdapter.sol";
import {AllChainAddresses as Addresses} from "@proposals/Addresses.sol";
import {LiveProposalCheck} from "@test/utils/LiveProposalCheck.sol";
import {MultichainGovernor} from "@protocol/governance/multichain/MultichainGovernor.sol";

contract LiveProposalsIntegrationTest is LiveProposalCheck {
    using stdStorage for StdStorage;
    using String for string;

    using Bytes for bytes;
    using Address for *;
    using ChainIds for uint256;

    /// @notice addresses contract
    Addresses addresses;

    /// @notice Multichain Governor address
    MultichainGovernor governor;

    function setUp() public override {
        super.setUp();

        MOONBEAM_FORK_ID.createForksAndSelect();

        addresses = new Addresses();
        vm.makePersistent(address(addresses));

        address governorAddress = addresses.getAddress(
            "MULTICHAIN_GOVERNOR_PROXY"
        );

        governor = MultichainGovernor(payable(governorAddress));
    }

    function testExecutingSucceededProposals() public {
        // execute proposals that are succeeded but not executed yet
        executeSucceededProposals(addresses, governor);
    }

    // checks that all live proposals execute successfully
    // execute the VAA in the temporal governor if it's a cross chain proposal
    // without mocking wormhole
    function testExecutingLiveProposals() public {
        // execute proposals that are in the vote or vote collection period
        executeLiveProposals(addresses, governor);
    }

    function testExecutingTemporalGovernorQueuedProposals() public {
        // execute proposals that are queued in the temporal governor but not executed yet
        executeTemporalGovernorQueuedProposals(addresses, governor);
    }

    // check that all live proposals execute successfully
    // mock wormhole to simulate the queue step
    function testExecutingLiveProposalsMockWormhole() public {
        /// ----------------------------------------------------------
        /// ---- Mock Wormhole Adapter (relayer + core bridge) --------
        /// ----------------------------------------------------------

        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter(
            new uint16[](0),
            new uint256[](0)
        );
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);
        wormholeRelayer.setMockChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        bytes32 mockAddr = bytes32(uint256(uint160(address(wormholeRelayer))));

        /// Override wormhole + relayer slots on all forks for governor,
        /// voteCollection, and xWELL adapter so _wormhole() returns the mock.
        /// Use _tryOverrideWormhole to handle contracts that may not yet be
        /// upgraded (wormhole() doesn't exist on old impls).

        /// --- Moonbeam ---
        vm.selectFork(MOONBEAM_FORK_ID);

        _tryOverrideWormhole(address(governor), mockAddr);
        vm.store(
            address(governor),
            bytes32(uint256(103)),
            mockAddr /// relayer slot (gasLimit stays 0 which is fine for mock)
        );

        address adapter = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        _tryOverrideWormhole(adapter, mockAddr);

        /// --- Base ---
        vm.selectFork(BASE_FORK_ID);
        address vcBase = addresses.getAddress("VOTE_COLLECTION_PROXY");
        _tryOverrideWormhole(vcBase, mockAddr);
        vm.store(vcBase, bytes32(0), mockAddr); /// relayer slot

        adapter = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        _tryOverrideWormhole(adapter, mockAddr);

        /// --- Optimism ---
        vm.selectFork(OPTIMISM_FORK_ID);
        address vcOpt = addresses.getAddress("VOTE_COLLECTION_PROXY");
        _tryOverrideWormhole(vcOpt, mockAddr);
        vm.store(vcOpt, bytes32(0), mockAddr); /// relayer slot

        adapter = addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY");
        _tryOverrideWormhole(adapter, mockAddr);

        vm.selectFork(MOONBEAM_FORK_ID);

        /// ----------------------------------------------------------
        /// ----------------------------------------------------------
        /// ----------------------------------------------------------

        executeLiveProposals(addresses, governor);
    }

    function testExecutingInDevelopmentProposals() public {
        // execute proposals that are not on chain yet
        ProposalMap.ProposalFields[] memory devProposals = proposalMap
            .getAllProposalsInDevelopment();

        if (devProposals.length == 0) {
            return;
        }

        // execute in the inverse order so that the lowest id is executed first
        for (uint256 i = devProposals.length; i > 0; i--) {
            proposalMap.setEnv(devProposals[i - 1].envPath);
            proposalMap.runProposal(addresses, devProposals[i - 1].path);
        }
    }

    /// @notice Try to override the wormhole slot on a contract via stdstore.
    ///         If the contract hasn't been upgraded yet and wormhole() doesn't
    ///         exist, the stdstore lookup will fail — catch and skip.
    function _tryOverrideWormhole(address target, bytes32 mockAddr) internal {
        (bool success, ) = target.staticcall(
            abi.encodeWithSignature("wormhole()")
        );
        if (success) {
            uint256 slot = stdstore.target(target).sig("wormhole()").find();
            vm.store(target, bytes32(slot), mockAddr);
        }
    }
}

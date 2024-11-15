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
        /// ---------------- Wormhole Relayer Etching ----------------
        /// ----------------------------------------------------------

        /// mock relayer so we can simulate bridging well
        WormholeRelayerAdapter wormholeRelayer = new WormholeRelayerAdapter();
        vm.makePersistent(address(wormholeRelayer));
        vm.label(address(wormholeRelayer), "MockWormholeRelayer");

        /// we need to set this so that the relayer mock knows that for the next sendPayloadToEvm
        /// call it must switch forks
        wormholeRelayer.setIsMultichainTest(true);
        wormholeRelayer.setSenderChainId(MOONBEAM_WORMHOLE_CHAIN_ID);

        // set mock as the wormholeRelayer address on bridge adapter
        WormholeBridgeAdapter wormholeBridgeAdapter = WormholeBridgeAdapter(
            addresses.getAddress("WORMHOLE_BRIDGE_ADAPTER_PROXY")
        );

        uint256 gasLimit = wormholeBridgeAdapter.gasLimit();

        // encode gasLimit and relayer address since is stored in a single slot
        // relayer is first due to how evm pack values into a single storage
        bytes32 encodedData = bytes32(
            (uint256(uint160(address(wormholeRelayer))) << 96) |
                uint256(gasLimit)
        );

        vm.selectFork(BASE_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(OPTIMISM_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

        vm.selectFork(MOONBEAM_FORK_ID);

        /// stores the wormhole mock address in the wormholeRelayer variable
        vm.store(
            address(wormholeBridgeAdapter),
            bytes32(uint256(153)),
            encodedData
        );

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
}
